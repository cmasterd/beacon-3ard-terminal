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
            { id: 1, code: "TEXT-LOG #01", title: "[PLACEHOLDER DOCUMENT TITLE 01]", desc: "[Placeholder summary for text log 01.]", body: "FROM: [SENDER]\nTO: [RECIPIENT]\nSUBJECT: [SUBJECT]\n\n[Placeholder body text for text log 01.]" },
            { id: 2, code: "TEXT-LOG #02", title: "[PLACEHOLDER DOCUMENT TITLE 02]", desc: "[Placeholder summary for text log 02.]", body: "[Placeholder body text for text log 02.]" },
            { id: 3, code: "TEXT-LOG #03", title: "[PLACEHOLDER DOCUMENT TITLE 03]", desc: "[Placeholder summary for text log 03.]", body: "[Placeholder body text for text log 03.]" }
        ]
    }
};
