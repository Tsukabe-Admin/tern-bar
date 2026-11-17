//! The Wayland side: watching the clipboard and putting an entry on it.
//!
//! An ordinary app only sees the clipboard while one of its windows has the
//! keyboard. A clipboard manager uses the *data-control* protocol instead,
//! which sees every change and can set the clipboard at any time. There are
//! two versions with the same requests and events: `ext_data_control_v1`, the
//! standard one, and the older `zwlr_data_control_v1` from wlroots. niri and
//! Hyprland offer both; the standard one is used when it is there.
//!
//! How it goes: the compositor announces each new clipboard content as an
//! *offer* with the types it comes in (`data_offer`, then one `offer` event
//! per type), then says it is now the clipboard (`selection`). Reading one
//! type means handing the app a pipe (`receive`). Setting the clipboard means
//! creating a *source* that lists its types and making it the selection; the
//! compositor then hands over a pipe for every paste (`send`), until another
//! app copies something (`cancelled`).

use std::os::fd::BorrowedFd;
use std::sync::Mutex;

use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_registry, wl_seat};
use wayland_client::{event_created_child, Connection, Dispatch, EventQueue, Proxy, QueueHandle};
use wayland_protocols::ext::data_control::v1::client::{
    ext_data_control_device_v1 as ext_device, ext_data_control_manager_v1 as ext_manager,
    ext_data_control_offer_v1 as ext_offer, ext_data_control_source_v1 as ext_source,
};
use wayland_protocols_wlr::data_control::v1::client::{
    zwlr_data_control_device_v1 as wlr_device, zwlr_data_control_manager_v1 as wlr_manager,
    zwlr_data_control_offer_v1 as wlr_offer, zwlr_data_control_source_v1 as wlr_source,
};

use super::Job;

/// The clipboard of the first seat, through whichever protocol version the
/// compositor has.
pub enum Clipboard {
    Ext {
        manager: ext_manager::ExtDataControlManagerV1,
        device: ext_device::ExtDataControlDeviceV1,
    },
    Wlr {
        manager: wlr_manager::ZwlrDataControlManagerV1,
        device: wlr_device::ZwlrDataControlDeviceV1,
    },
}

/// Content this job put on the clipboard.
#[derive(PartialEq)]
pub enum Source {
    Ext(ext_source::ExtDataControlSourceV1),
    Wlr(wlr_source::ZwlrDataControlSourceV1),
}

/// Content an app put on the clipboard.
pub enum Offer {
    Ext(ext_offer::ExtDataControlOfferV1),
    Wlr(wlr_offer::ZwlrDataControlOfferV1),
}

/// The types an offer comes in, gathered from its `offer` events.
#[derive(Default)]
pub struct OfferTypes(Mutex<Vec<String>>);

pub enum ConnectError {
    /// The compositor has neither version of data control.
    NoProtocol,
    Failed(String),
}

/// Connects to the compositor named by WAYLAND_DISPLAY and starts watching
/// the clipboard. Its events arrive on the queue returned.
pub fn connect() -> Result<(Connection, EventQueue<Job>, Clipboard), ConnectError> {
    let failed =
        |what: &str, err: &dyn std::fmt::Display| ConnectError::Failed(format!("{what}: {err}"));
    let connection = Connection::connect_to_env()
        .map_err(|err| failed("cannot reach the Wayland compositor", &err))?;
    let (globals, queue) = registry_queue_init::<Job>(&connection)
        .map_err(|err| failed("cannot list what the compositor offers", &err))?;
    let qh = queue.handle();
    let seat: wl_seat::WlSeat = globals
        .bind(&qh, 1..=1, ())
        .map_err(|err| failed("the compositor has no seat", &err))?;
    let clipboard = if let Ok(manager) =
        globals.bind::<ext_manager::ExtDataControlManagerV1, _, _>(&qh, 1..=1, ())
    {
        let device = manager.get_data_device(&seat, &qh, ());
        Clipboard::Ext { manager, device }
    } else if let Ok(manager) =
        globals.bind::<wlr_manager::ZwlrDataControlManagerV1, _, _>(&qh, 1..=2, ())
    {
        let device = manager.get_data_device(&seat, &qh, ());
        Clipboard::Wlr { manager, device }
    } else {
        return Err(ConnectError::NoProtocol);
    };
    Ok((connection, queue, clipboard))
}

impl Clipboard {
    /// Puts content on the clipboard under the given types.
    pub fn offer(&self, types: &[&str], qh: &QueueHandle<Job>) -> Source {
        match self {
            Clipboard::Ext { manager, device } => {
                let source = manager.create_data_source(qh, ());
                for name in types {
                    source.offer(name.to_string());
                }
                device.set_selection(Some(&source));
                Source::Ext(source)
            }
            Clipboard::Wlr { manager, device } => {
                let source = manager.create_data_source(qh, ());
                for name in types {
                    source.offer(name.to_string());
                }
                device.set_selection(Some(&source));
                Source::Wlr(source)
            }
        }
    }
}

impl Source {
    pub fn destroy(&self) {
        match self {
            Source::Ext(source) => source.destroy(),
            Source::Wlr(source) => source.destroy(),
        }
    }
}

impl Offer {
    pub fn types(&self) -> Vec<String> {
        let types = match self {
            Offer::Ext(offer) => offer.data::<OfferTypes>(),
            Offer::Wlr(offer) => offer.data::<OfferTypes>(),
        };
        types.map_or_else(Vec::new, |types| types.0.lock().unwrap().clone())
    }

    /// Asks the app to write the content, as `mime`, into `pipe`.
    pub fn receive(&self, mime: &str, pipe: BorrowedFd<'_>) {
        match self {
            Offer::Ext(offer) => offer.receive(mime.to_owned(), pipe),
            Offer::Wlr(offer) => offer.receive(mime.to_owned(), pipe),
        }
    }

    pub fn destroy(&self) {
        match self {
            Offer::Ext(offer) => offer.destroy(),
            Offer::Wlr(offer) => offer.destroy(),
        }
    }
}

// What the compositor says, passed on to the job (mod.rs).

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for Job {
    fn event(
        _: &mut Job,
        _: &wl_registry::WlRegistry,
        _: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for Job {
    fn event(
        _: &mut Job,
        _: &wl_seat::WlSeat,
        _: wl_seat::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
    }
}

impl Dispatch<ext_manager::ExtDataControlManagerV1, ()> for Job {
    fn event(
        _: &mut Job,
        _: &ext_manager::ExtDataControlManagerV1,
        _: ext_manager::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
    }
}

impl Dispatch<ext_device::ExtDataControlDeviceV1, ()> for Job {
    fn event(
        job: &mut Job,
        _: &ext_device::ExtDataControlDeviceV1,
        event: ext_device::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
        match event {
            ext_device::Event::Selection { id } => job.selection(id.map(Offer::Ext)),
            // The primary selection (text selected with the mouse) is not
            // kept; its offers are let go at once.
            ext_device::Event::PrimarySelection { id: Some(offer) } => offer.destroy(),
            ext_device::Event::Finished => job.finished(),
            _ => {}
        }
    }

    event_created_child!(Job, ext_device::ExtDataControlDeviceV1, [
        ext_device::EVT_DATA_OFFER_OPCODE => (ext_offer::ExtDataControlOfferV1, OfferTypes::default()),
    ]);
}

impl Dispatch<ext_offer::ExtDataControlOfferV1, OfferTypes> for Job {
    fn event(
        _: &mut Job,
        _: &ext_offer::ExtDataControlOfferV1,
        event: ext_offer::Event,
        types: &OfferTypes,
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
        if let ext_offer::Event::Offer { mime_type } = event {
            types.0.lock().unwrap().push(mime_type);
        }
    }
}

impl Dispatch<ext_source::ExtDataControlSourceV1, ()> for Job {
    fn event(
        job: &mut Job,
        source: &ext_source::ExtDataControlSourceV1,
        event: ext_source::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
        let this = Source::Ext(source.clone());
        match event {
            ext_source::Event::Send { fd, .. } => job.paste(&this, fd),
            ext_source::Event::Cancelled => job.cancelled(this),
            _ => {}
        }
    }
}

impl Dispatch<wlr_manager::ZwlrDataControlManagerV1, ()> for Job {
    fn event(
        _: &mut Job,
        _: &wlr_manager::ZwlrDataControlManagerV1,
        _: wlr_manager::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
    }
}

impl Dispatch<wlr_device::ZwlrDataControlDeviceV1, ()> for Job {
    fn event(
        job: &mut Job,
        _: &wlr_device::ZwlrDataControlDeviceV1,
        event: wlr_device::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
        match event {
            wlr_device::Event::Selection { id } => job.selection(id.map(Offer::Wlr)),
            wlr_device::Event::PrimarySelection { id: Some(offer) } => offer.destroy(),
            wlr_device::Event::Finished => job.finished(),
            _ => {}
        }
    }

    event_created_child!(Job, wlr_device::ZwlrDataControlDeviceV1, [
        wlr_device::EVT_DATA_OFFER_OPCODE => (wlr_offer::ZwlrDataControlOfferV1, OfferTypes::default()),
    ]);
}

impl Dispatch<wlr_offer::ZwlrDataControlOfferV1, OfferTypes> for Job {
    fn event(
        _: &mut Job,
        _: &wlr_offer::ZwlrDataControlOfferV1,
        event: wlr_offer::Event,
        types: &OfferTypes,
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
        if let wlr_offer::Event::Offer { mime_type } = event {
            types.0.lock().unwrap().push(mime_type);
        }
    }
}

impl Dispatch<wlr_source::ZwlrDataControlSourceV1, ()> for Job {
    fn event(
        job: &mut Job,
        source: &wlr_source::ZwlrDataControlSourceV1,
        event: wlr_source::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Job>,
    ) {
        let this = Source::Wlr(source.clone());
        match event {
            wlr_source::Event::Send { fd, .. } => job.paste(&this, fd),
            wlr_source::Event::Cancelled => job.cancelled(this),
            _ => {}
        }
    }
}
