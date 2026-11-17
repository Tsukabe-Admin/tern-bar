//! Clipboard contents travel through pipes: an app writes what it copied into
//! one end, and a paste reads it from the other. Both ends here are
//! non-blocking, so a slow or stuck app never holds up the job: each pump
//! moves what it can and says whether to come back when the pipe is ready.

use std::io;
use std::os::fd::AsFd;
use std::rc::Rc;

use rustix::io::Errno;

#[derive(Debug, PartialEq, Eq)]
pub enum Pump {
    /// Nothing more for now: come back when the pipe is ready again.
    Pending,
    Done,
    /// More than the limit arrived; the rest is not read.
    TooBig,
}

/// How much is asked for per read.
const CHUNK: usize = 64 * 1024;

/// What an app is sending.
pub struct Incoming {
    pub data: Vec<u8>,
    limit: usize,
}

impl Incoming {
    pub fn new(limit: usize) -> Incoming {
        Incoming {
            data: Vec::new(),
            limit,
        }
    }

    /// Reads what has arrived, straight into `data`. Done when the app
    /// closed its end.
    pub fn pump(&mut self, pipe: impl AsFd) -> io::Result<Pump> {
        loop {
            self.data.reserve(CHUNK);
            match rustix::io::read(&pipe, rustix::buffer::spare_capacity(&mut self.data)) {
                Ok(0) => return Ok(Pump::Done),
                Ok(_) if self.data.len() > self.limit => return Ok(Pump::TooBig),
                Ok(_) | Err(Errno::INTR) => {}
                Err(Errno::AGAIN) => return Ok(Pump::Pending),
                Err(err) => return Err(err.into()),
            }
        }
    }
}

/// An entry going to an app that pastes it.
pub struct Outgoing {
    data: Rc<Vec<u8>>,
    sent: usize,
}

impl Outgoing {
    pub fn new(data: Rc<Vec<u8>>) -> Outgoing {
        Outgoing { data, sent: 0 }
    }

    /// Writes as much as the pipe takes. An app that closed its end before
    /// reading everything gives an error (EPIPE).
    pub fn pump(&mut self, pipe: impl AsFd) -> io::Result<Pump> {
        while self.sent < self.data.len() {
            match rustix::io::write(&pipe, &self.data[self.sent..]) {
                Ok(written) => self.sent += written,
                Err(Errno::INTR) => {}
                Err(Errno::AGAIN) => return Ok(Pump::Pending),
                Err(err) => return Err(err.into()),
            }
        }
        Ok(Pump::Done)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::os::fd::OwnedFd;

    fn pipe() -> (OwnedFd, OwnedFd) {
        let (reader, writer) = std::io::pipe().unwrap();
        (reader.into(), writer.into())
    }

    /// Pumps until there is an answer other than "nothing yet". Another test
    /// that is starting a program can hold a copy of a pipe end for a moment,
    /// until that program starts, so the end of a pipe can come a little late.
    fn settle(mut pump: impl FnMut() -> io::Result<Pump>) -> io::Result<Pump> {
        let started = std::time::Instant::now();
        loop {
            match pump() {
                Ok(Pump::Pending) if started.elapsed().as_secs() < 5 => {
                    std::thread::sleep(std::time::Duration::from_millis(1))
                }
                answer => return answer,
            }
        }
    }

    #[test]
    fn reads_until_the_writer_closes() {
        let (reader, writer) = pipe();
        rustix::io::ioctl_fionbio(&reader, true).unwrap();
        let mut incoming = Incoming::new(1000);
        assert_eq!(incoming.pump(&reader).unwrap(), Pump::Pending);
        let mut writer = std::fs::File::from(writer);
        writer.write_all(b"hello ").unwrap();
        assert_eq!(incoming.pump(&reader).unwrap(), Pump::Pending);
        writer.write_all(b"world").unwrap();
        drop(writer);
        assert_eq!(settle(|| incoming.pump(&reader)).unwrap(), Pump::Done);
        assert_eq!(incoming.data, b"hello world");
    }

    #[test]
    fn stops_reading_past_the_limit() {
        let (reader, writer) = pipe();
        rustix::io::ioctl_fionbio(&reader, true).unwrap();
        let sender = std::thread::spawn(move || {
            let mut writer = std::fs::File::from(writer);
            // A pipe holds 64 KiB, so this waits for the reader, and fails
            // once the reader has stopped and gone.
            writer.write_all(&vec![b'x'; 1_000_000]).is_err()
        });
        let mut incoming = Incoming::new(100_000);
        let end = loop {
            match incoming.pump(&reader).unwrap() {
                Pump::Pending => std::thread::sleep(std::time::Duration::from_millis(1)),
                end => break end,
            }
        };
        assert_eq!(end, Pump::TooBig);
        assert!(incoming.data.len() > 100_000 && incoming.data.len() < 300_000);
        drop(reader);
        assert!(sender.join().unwrap(), "the sender was cut off");
    }

    #[test]
    fn exactly_the_limit_is_accepted() {
        let (reader, writer) = pipe();
        rustix::io::ioctl_fionbio(&reader, true).unwrap();
        let mut writer = std::fs::File::from(writer);
        writer.write_all(&[b'y'; 1000]).unwrap();
        drop(writer);
        let mut incoming = Incoming::new(1000);
        assert_eq!(settle(|| incoming.pump(&reader)).unwrap(), Pump::Done);
        assert_eq!(incoming.data.len(), 1000);
        let (reader, writer) = pipe();
        rustix::io::ioctl_fionbio(&reader, true).unwrap();
        let mut writer = std::fs::File::from(writer);
        writer.write_all(&[b'y'; 1001]).unwrap();
        drop(writer);
        let mut incoming = Incoming::new(1000);
        assert_eq!(settle(|| incoming.pump(&reader)).unwrap(), Pump::TooBig);
    }

    #[test]
    fn writes_without_waiting_for_a_slow_reader() {
        let (reader, writer) = pipe();
        rustix::io::ioctl_fionbio(&writer, true).unwrap();
        // Far more than a pipe holds (64 KiB unless raised).
        let data: Vec<u8> = (0..4_000_000u32).map(|n| n as u8).collect();
        let mut outgoing = Outgoing::new(Rc::new(data.clone()));
        assert_eq!(outgoing.pump(&writer).unwrap(), Pump::Pending);
        let receiver = std::thread::spawn(move || {
            let mut got = Vec::new();
            std::fs::File::from(reader).read_to_end(&mut got).unwrap();
            got
        });
        loop {
            match outgoing.pump(&writer).unwrap() {
                Pump::Pending => std::thread::sleep(std::time::Duration::from_millis(1)),
                Pump::Done => break,
                Pump::TooBig => unreachable!(),
            }
        }
        drop(writer);
        assert_eq!(receiver.join().unwrap(), data);
    }

    #[test]
    fn a_reader_that_left_is_an_error() {
        let (reader, writer) = pipe();
        rustix::io::ioctl_fionbio(&writer, true).unwrap();
        drop(reader);
        // Each try is a fresh paste, as a write that got through is done.
        let answer = settle(
            || match Outgoing::new(Rc::new(b"text".to_vec())).pump(&writer) {
                Ok(Pump::Done) => Ok(Pump::Pending),
                answer => answer,
            },
        );
        assert!(answer.is_err());
    }
}
