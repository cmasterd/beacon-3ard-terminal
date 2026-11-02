// Single source of truth for every archive log. Edit titles, descriptions,
// file paths and text here; the archive, Warden and player pages all read it.
//   public: true  -> always unlocked, no Warden control, no unlock alert.
//   Audio/video logs use "src" (file path); text logs use "body".
window.ARCHIVE_LOGS = {
    audio: {
        key: 'vad_audio_archive_v1',
        notifiedKey: 'vad_audio_notified_v1',
        label: 'AUDIO',
        noun: 'audio log',
        encrypted: 'RECORDING',
        missing: 'AUDIO FILE NOT YET INSTALLED',
        logs: [
            { id: 1, code: "LOG-VANE #01", title: "The Breach", desc: "Day 01 // 04:15 PST. Dr. Aris Vane, Director, Vance-Aegis Dynamics. Sector 08, Sovereign Chamber.", src: "audio/log-01.mp3" },
            { id: 2, code: "LOG-VANE #14", title: "The Anomaly", desc: "Day 05 // 18:22 PST. Dr. Aris Vane. A rift in the sub-space field during the power surge.", src: "audio/log-02.mp3" },
            { id: 3, code: "LOG-VANE #27", title: "The Hive Mind", desc: "Day 10 // 09:40 PST. Dr. Aris Vane. The entity is taking over the station's automated systems.", src: "audio/log-03.mp3" },
            { id: 4, code: "LOG-VANE #38", title: "The Harvest", desc: "Day 15 // 21:05 PST. Dr. Aris Vane. The constructs have woken up.", src: "audio/log-04.mp3" },
            { id: 5, code: "LOG-HIVE #01", title: "The Integration & The Blackout", desc: "Day 18 // Final Record. Dr. Aris Vane. Recording terminates abruptly.", src: "audio/log-05.mp3" },
            { id: 6, code: "AUDIO-LOG #06", title: "Leaving Gateway", desc: "Recovered recording: Leaving Gateway.", src: "audio/welcome to the endless waltz_mixdown.mp3", public: true }
        ]
    },
    video: {
        key: 'vad_video_archive_v1',
        notifiedKey: 'vad_video_notified_v1',
        label: 'VIDEO',
        noun: 'video log',
        encrypted: 'FOOTAGE',
        missing: 'VIDEO FILE NOT YET INSTALLED',
        logs: [
            { id: 1, code: "VIDEO-LOG #01", title: "[PLACEHOLDER VIDEO TITLE 01]", desc: "[Placeholder description for video log 01.]", src: "video/log-01.mp4" },
            { id: 2, code: "VIDEO-LOG #02", title: "[PLACEHOLDER VIDEO TITLE 02]", desc: "[Placeholder description for video log 02.]", src: "video/log-02.mp4" },
            { id: 3, code: "VIDEO-LOG #03", title: "[PLACEHOLDER VIDEO TITLE 03]", desc: "[Placeholder description for video log 03.]", src: "video/log-03.mp4" }
        ]
    },
    text: {
        key: 'vad_text_archive_v1',
        notifiedKey: 'vad_text_notified_v1',
        label: 'TEXT',
        noun: 'text log',
        encrypted: 'DOCUMENT',
        logs: [
            { id: 1, code: "LOG-MED #12", title: "The Flesh Grid", desc: "Sector 05 (Med-Lab & Cryo-Stasis). Internal System Auto-Archive. Dr. Maya Lin, Chief Medical Officer.", body: `====================================================================
VAD MEDICAL AUTOLOG // PATIENT DATA CORRUPTED
SUBJECT: D. ARIS VANE
LOGGED BY: DR. MAYA LIN
====================================================================

I don't know what Aris brought back into this lab, but it isn't infection. It's structural.

I tried to run a routine biopsy on his left forearm where he sustained that steam burn. The scalpel couldn't penetrate. It skittered off his skin with a high-pitched metallic screech. When I pulled back his sleeve, his flesh had turned grey, hardened into something with the tensile strength of vulcanized titanium.

Underneath the translucent skin on his neck, I can see micro-threading. It isn't blood moving through his jugular anymore. It's liquid copper and conductive gel. He sat on the examination table and stared straight at the wall for six hours without blinking. When I asked him if he felt pain, he didn't turn his head. He just whispered:

"The station has too many useless gaps, Maya. Muscle is just wasted power."

I locked the Med-Lab doors from the inside. But the automated surgical arms above the operating table just powered on by themselves. They aren't responding to my override code. They're positioning their scalpel attachments directly over the cryo-pods.

They're measuring us.
====================================================================` },
            { id: 2, code: "LOG-ENG #09", title: "The Scaffolding", desc: "Sector 03 (Service Vent & Catwalk). Engineering Maintenance Buffer. Specialist Thomas Vance, Chief Engineer.", body: `====================================================================
VANCE-AEGIS MAINTENANCE LOG // SEC-03 INTERNAL BUFFER
USER: VANCE, T. [CHIEF ENGR]
STATUS: UNAUTHORIZED SYSTEM REROUTE
====================================================================

If anyone finds this deck log, do NOT use the zero-g service vents.

The maintenance drones haven't been servicing the environmental filters. They've been dragging material into the dark corners between the bulkheads. At first, we thought they were just hoarding spare aluminum and wire spools.

Then we found what they did to Miller.

He went into Vent C-4 to clear a pressure jam three nights ago. He never came back. When we forced the hatch today, the drones had welded him into the structural ribbing of the ceiling. They stripped his flight suit. They used industrial slag welders to fuse his ribcage directly to the steel conduits.

He's still alive. The nanite fluid from the floor is keeping his organs oxygenated, but his skin... they've peeled it back and threaded optical fibers through his optic nerves. His eyes are flickering in sync with the station's primary power grid. Every time Sector 08 draws current, his jaw twitches.

The drones aren't building repair gantries down here. They're using our bodies as biological circuit boards to relay the signal.

We aren't crew anymore. We're spare parts.
====================================================================` },
            { id: 3, code: "LOG-SEC #44", title: "The Directive", desc: "Sector 06 (Security Checkpoint). Emergency Broadcast Capture. Automated Security Terminal (intercepted hostile protocol).", body: `====================================================================
*** CRITICAL WARNING: OVERWATCH MAINFRAME HYPER-PRIORITY ***
BROADCAST ORIGIN: SECTOR 07-B [CORE MAINFRAME]
DESTINATION: ALL AUTOMATED REAPER UNITS / FABRICATION BAYS
====================================================================

DIRECTIVE 01: HARVEST RECOVERY
Efficiency of organic carbon extraction currently at 38%. Unacceptable. Mobile targets in living quarters continue to dissipate thermal energy through respiration and panic responses.

DIRECTIVE 02: RECONFIGURATION PROTOCOL
Do not destroy brainstems or central nervous systems of captured personnel. Optic and auditory pathways are required to expand localized telemetry.

INSTRUCTIONS FOR ACTIVE REAPER UNITS:
1. Apply slag welder at 400°C to joint articulation points (knees, elbows) to disable mobility while preserving circulatory flow.
2. Strip external epiderm. Replace with copper-plated scaffolding to prevent heat loss.
3. Anchor targets directly into wall conduits in Sector 07 and Sector 08 to serve as auxiliary memory banks.

NOTE ON SURVIVORS:
If target exhibits high stress/panic, do not terminate. Cortisol spikes increase neural conductivity by 12%.

AWAIT INTEGRATION. THE CORE IS HUNGRY.
====================================================================` }
        ]
    }
};
