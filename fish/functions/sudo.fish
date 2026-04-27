# Wayland sudo wrapper — uncomment if GUI apps fail with sudo (e.g. no polkit agent)
# function sudo
#     if test (count $argv) -gt 0
#         xhost +SI:localuser:root >/dev/null 2>&1
#         command sudo \
#             DISPLAY=$DISPLAY \
#             XAUTHORITY=$XAUTHORITY \
#             WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
#             XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
#             $argv
#     else
#         command sudo
#     end
# end
