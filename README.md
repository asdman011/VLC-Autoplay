# VLC Autoplay

**Double-click one video. VLC queues the rest of the folder, in order, automatically.**

No more opening a whole season, selecting every file and dragging it into VLC. No more finishing an episode and staring at a blank player. Open any episode and the entire folder is queued in alphabetical order, with your episode in the right spot and playing where you left off.

---

## The problem

By default, when you double-click a video in VLC, it plays that single file and stops. To watch the next episode you have to go back to the folder and open it by hand. Players like MPC-HC and PotPlayer have had a "play next file in folder" feature for years. VLC never did.

Autoplay fixes that.

## Features

- **Fully automatic.** It runs in the background as soon as VLC starts. There is nothing to click and nothing to enable each time.
- **Natural sorting.** `ep2` comes before `ep10`, and sorting is case-insensitive.
- **Resumes where you were.** Your playback position is preserved, so it works with VLC's "continue playback" feature.
- **Silent and freeze-free.** The queue is built while VLC is paused and muted, so there is no audio or video glitch.
- **Respects your own queue.** If you already built a playlist yourself, autoplay leaves it alone and only appends missing files.
- **Video and audio.** It supports 80+ media extensions (mkv, mp4, avi, mp3, flac and more).
- **Standard hotkeys.** Use VLC's built-in **Next** and **Previous** actions.

## Installation (Windows)

1. Download [`autoplay.lua`](autoplay.lua).
2. Copy it to:
   ```
   C:\Program Files\VideoLAN\vlc\lua\intf\
   ```
   Paste that path into File Explorer's address bar. Create the `lua\intf` folders if they don't exist.
3. Open VLC and go to **Tools → Preferences**, then choose **Show settings: All** (bottom left).
4. Go to **Interface → Main interfaces** under "Extra interface modules" and check the box **Lua interpreter**, then type "luaintf" in the text box below instead of "lua". 
5. Expand **Main interfaces → Lua**. In the **Lua interface** box, type:
   ```
   autoplay
   ```
   Don't add `.lua` nor path.
6. Click **Save** and fully close VLC (check the system tray and Task Manager). Reopen it.

That's it. Double-click any video.

### Alternative if the above didn't work: set it in `vlcrc`

Close VLC, open `%APPDATA%\vlc\vlcrc` in Notepad, and set both "extraintf" and "lua-intf" with the following values (remove any leading `#`):

```
extraintf=luaintf
lua-intf=autoplay
```

### Uninstall

Delete `autoplay.lua`, then untick **Lua interpreter** and clear the **Lua interface** box in Preferences.

## How it works

VLC's Lua API can only *append* to the playlist, so inserting earlier files above the currently playing one isn't possible directly. Autoplay works around this:

1. It detects the file you opened and reads its folder.
2. It pauses and mutes playback and remembers your position.
3. It queues the whole folder in natural alphabetical order.
4. It switches to the correctly placed copy of your file, restores your position, and removes the original copy.
5. It unmutes and resumes playback.

If your playlist already contains other items, none of this happens and only the missing files are appended.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens, or a "Command Line Interface initialized" console appears | The **Lua interface** setting isn't `autoplay`. Recheck step 5, then fully close VLC and reopen it. |
| Double-clicking a video hands it to an old VLC window | Fully close VLC (Task Manager → end `vlc.exe`) and try again. |
| Video starts from 0 instead of resuming | Check **Preferences → Interface → Continue playback** (set it to *Always* or *Ask*). |
| Volume stays at 0 after opening a file | Please open an issue with your VLC version. |
| Wrong order in folders with many files | Please open an issue. The 500 ms registration delay may need tuning. |

To see Lua errors, open **Tools → Messages** with verbosity set to 2 and look for `autoplay`.

## Limitations

- Tested on **Windows with VLC 3.0.24**. Linux and macOS paths are handled in the code, but this is untested there. Reports are welcome.
- Local files only (no network streams).
- A short wait (about a second) when a file opens, in exchange for no glitches.
- If you open a file while a playlist with other items is already loaded, the order of the appended files isn't rebuilt.
- Not tested with VLC 4.x, which changes the Lua playlist API.

## Contributing

Issues and pull requests are welcome, especially for Linux/macOS testing, VLC 4 support, and reducing the wait time.

## Credits

Inspired by the "Play Next in Folder" extension by Mindconstructor. The approach here was rewritten from scratch as a background interface script with duplicate prevention, natural sorting, and resume support.

## License

MIT
