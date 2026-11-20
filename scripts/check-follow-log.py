#!/usr/bin/env python3
"""Check observations from the native fixture; does not drive any application."""
import json
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'output/follow-test/events.jsonl')
entries = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
start = max(i for i, entry in enumerate(entries) if entry['event'] == 'helper_started')
entries = entries[start:]
frames = [entry for entry in entries if entry['event'] == 'follow']
assert frames, 'No native follow observations'
assert all(entry['target'] == entry['overlay'] for entry in frames), 'Overlay diverged from target'
assert len({(entry['target']['x'], entry['target']['y']) for entry in frames}) > 1, 'No observed movement'
assert len({(entry['target']['width'], entry['target']['height']) for entry in frames}) > 1, 'No observed resize'
hidden = [entry.get('reason') for entry in entries if entry['event'] == 'overlay_hidden']
assert 'window_offscreen' in hidden, 'No minimize/offscreen observation'
assert 'another_window_frontmost' in hidden, 'No foreground/window switch observation'
assert sum(entry['event'] == 'overlay_visible' for entry in entries) >= 2, 'No restore observation'
assert any(entry['event'] == 'fade_started' and entry.get('reason') == 'intro_complete' and
           entry.get('clickThrough') is True for entry in entries), 'No automatic fade observation'
assert any(entry['event'] == 'overlay_finished' and entry.get('reason') == 'intro_complete'
           for entry in entries), 'No automatic cleanup observation'
active_id = None
for entry in entries:
    if entry['event'] == 'overlay_created':
        assert active_id is None, 'Created another overlay before closing the pinned one'
        active_id = entry['window']
    elif entry['event'] == 'follow':
        assert entry['window'] == active_id, 'Changed pinned window during playback'
    elif entry['event'] == 'overlay_finished':
        active_id = None
print(json.dumps({'native_follow_frames': len(frames), 'matching_boundaries': True,
                  'movement': True, 'resize': True, 'hide_and_restore': True,
                  'window_pin': True, 'automatic_fade_and_cleanup': True}, ensure_ascii=False, indent=2))
