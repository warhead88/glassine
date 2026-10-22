# dmgbuild settings for scripts/release.sh: a Finder window with Glassine on the left,
# an Applications link on the right and an arrow between them — drag to install.
# `app` and `background` are passed with -D by release.sh.
import os.path

app = defines["app"]  # noqa: F821 — provided by dmgbuild
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (640, 400))  # matches Design/tools/dmg-background.swift
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 150),
    "Applications": (470, 150),
}
