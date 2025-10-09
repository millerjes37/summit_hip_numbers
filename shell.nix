{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    pkg-config
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    # GUI dependencies for eframe/winit (X11 only)
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
    libxkbcommon
    libGL
    mesa
    libglvnd
  ];

  # Force X11 backend for winit to avoid Wayland issues
  WINIT_UNIX_BACKEND = "x11";
  XDG_SESSION_TYPE = "x11";
  GDK_BACKEND = "x11";
  QT_QPA_PLATFORM = "x11";

  # Set library path for GUI libraries
  LD_LIBRARY_PATH = with pkgs; lib.makeLibraryPath [
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
    libxkbcommon
    libGL
    mesa
    libglvnd
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
  ];
}