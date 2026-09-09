# Stone — a tide colour preset built from quickshell/Theme.qml.
#
# Format matches tide's own configure/configs/*.fish: one "variable value"
# pair per line, so `_load_config` can source it directly. Background colours
# stay `normal`, which keeps the Lean shape — colour is carried entirely by
# the foreground.
#
# Palette (Theme.qml):
#   fg      fafaf9   fgDim  e7e5e4   fgMuted d6d3d1
#   muted   a8a29e   deep   78716c   disabled 57534e
#   border  3a3633   borderStrong 44403c
#   blue 3b82f6  blueBright 60a5fa  green 22c55e  red ef4444
#   orange f97316  yellow eab308  purple a78bfa  pink f472b6
#   teal 34d399  slate 94a3b8
#
# Semantics follow the shell's: green = ok, yellow = warn, red = danger,
# accentPrimary (blue) = the thing you are looking at, which here is the path.
# Tool badges keep a hue near their usual brand colour so they stay
# distinguishable, but every value comes from the palette.

tide_character_color 22c55e
tide_character_color_failure ef4444

tide_pwd_bg_color normal
tide_pwd_color_dirs 3b82f6
tide_pwd_color_anchors 60a5fa
tide_pwd_color_truncated_dirs 78716c

tide_git_bg_color normal
tide_git_bg_color_unstable normal
tide_git_bg_color_urgent normal
tide_git_color_branch 34d399
tide_git_color_conflicted ef4444
tide_git_color_dirty eab308
tide_git_color_operation ef4444
tide_git_color_staged f97316
tide_git_color_stash a78bfa
tide_git_color_untracked 94a3b8
tide_git_color_upstream 34d399

tide_status_bg_color normal
tide_status_bg_color_failure normal
tide_status_color 22c55e
tide_status_color_failure ef4444

tide_cmd_duration_bg_color normal
tide_cmd_duration_color 78716c

tide_context_bg_color normal
tide_context_color_default a8a29e
tide_context_color_root ef4444
tide_context_color_ssh f97316

tide_jobs_bg_color normal
tide_jobs_color 34d399

tide_time_bg_color normal
tide_time_color 78716c

tide_os_bg_color normal
tide_os_color d6d3d1

tide_shlvl_bg_color normal
tide_shlvl_color a8a29e

tide_private_mode_bg_color normal
tide_private_mode_color a78bfa

tide_direnv_bg_color normal
tide_direnv_bg_color_denied normal
tide_direnv_color eab308
tide_direnv_color_denied ef4444

tide_vi_mode_bg_color_default normal
tide_vi_mode_bg_color_insert normal
tide_vi_mode_bg_color_replace normal
tide_vi_mode_bg_color_visual normal
tide_vi_mode_color_default 94a3b8
tide_vi_mode_color_insert 22c55e
tide_vi_mode_color_replace f97316
tide_vi_mode_color_visual a78bfa

tide_distrobox_bg_color normal
tide_distrobox_color f472b6
tide_toolbox_bg_color normal
tide_toolbox_color f472b6

tide_docker_bg_color normal
tide_docker_color 3b82f6
tide_kubectl_bg_color normal
tide_kubectl_color 3b82f6
tide_gcloud_bg_color normal
tide_gcloud_color 3b82f6
tide_aws_bg_color normal
tide_aws_color f97316
tide_terraform_bg_color normal
tide_terraform_color a78bfa
tide_pulumi_bg_color normal
tide_pulumi_color a78bfa
tide_nix_shell_bg_color normal
tide_nix_shell_color 60a5fa

tide_node_bg_color normal
tide_node_color 22c55e
tide_bun_bg_color normal
tide_bun_color e7e5e4
tide_python_bg_color normal
tide_python_color eab308
tide_rustc_bg_color normal
tide_rustc_color f97316
tide_go_bg_color normal
tide_go_color 34d399
tide_java_bg_color normal
tide_java_color ef4444
tide_php_bg_color normal
tide_php_color a78bfa
tide_ruby_bg_color normal
tide_ruby_color ef4444
tide_elixir_bg_color normal
tide_elixir_color a78bfa
tide_crystal_bg_color normal
tide_crystal_color fafaf9
tide_zig_bg_color normal
tide_zig_color f97316

tide_prompt_color_frame_and_connection 3a3633
tide_prompt_color_separator_same_color 44403c
