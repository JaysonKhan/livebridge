# dmgbuild settings for the macOS installer window. scripts/make-dmg.sh passes `app` and `background` with -D.
# Icon centres must match the arrow in scripts/dmg/background.swift.
import os.path

application = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821
# The frame includes the title bar and Finder's bottom bar, which macOS 26 shows even with show_status_bar False;
# the content area left over is the background's 660 × 420.
window_rect = ((200, 140), (660, 474))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

# The leading dot does not hide these two from every Finder; the hidden flag does.
hide = [".background.tiff", ".VolumeIcon.icns"]

icon_size = 112
text_size = 13
arrange_by = None
icon_locations = {
    app_name: (170, 196),
    "Applications": (490, 196),
    # Below the window, for people who have hidden files shown in Finder.
    ".background.tiff": (170, 900),
    ".VolumeIcon.icns": (490, 900),
}
