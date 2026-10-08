# dmgbuild settings for AutoHush's disk image, used by Scripts/build-dmg.sh,
# which passes the paths: -D app=<AutoHush.app> -D background=<.tiff>
# -D icon=<.icns>. dmgbuild writes the window's layout into the volume's
# .DS_Store itself, without Finder.
#
# The window is 640 × 480 points plus its title bar; the icon centres must
# match Scripts/lib/dmg-background.swift, which draws the background.

app = defines["app"]  # noqa: F821 (given by dmgbuild)
background = defines.get("background") or None  # noqa: F821
icon = defines.get("icon") or None  # noqa: F821

format = "UDZO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}

# Where the window opens, as Finder saved it for 0.8.2 (bottom-left origin).
window_rect = ((200, 489), (640, 508))
default_view = "icon-view"
show_status_bar = False
show_tab_view = True
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0
arrange_by = None
icon_size = 112
text_size = 13
label_pos = "bottom"
show_icon_preview = True

icon_locations = {
    "AutoHush.app": (170, 200),
    "Applications": (470, 200),
    # The volume's own files, below the window, out of sight for people who
    # show hidden files.
    ".background.tiff": (160, 640),
    ".fseventsd": (320, 640),
    ".VolumeIcon.icns": (480, 640),
}
