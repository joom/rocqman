(** * SDL2 bindings for Crane extraction.

    Provides Rocq axioms and IO wrappers for SDL2 functions,
    plus a small number of non-SDL extraction helpers used by Rocqman.

    Usage: [From RocqmanGame Require Import SDL.]

    Follows the same pattern as Crane's IO.v and Vector.v:
    axiom types and IO operations with extraction mappings. *)

From Corelib Require Import PrimString.
From Stdlib Require Import Lists.List.
Import ListNotations.
From Crane Require Import Mapping.NatIntStd.
From Crane Require Import Mapping.Std Monads.ITree Monads.IO.
From Crane Require Extraction.

(** * Integer math utilities

    Extraction helpers that Rocqman still needs and that are not
    already exposed in the current mapping set. *)

(** Test bit [n] of a natural number (zero-indexed from the LSB). *)
Definition nat_testbit : nat -> nat -> bool := Nat.testbit.

(** Convert a natural number to its decimal digits using a fuel argument
    to keep the recursion structurally decreasing. *)
Fixpoint nat_digit_list_aux (fuel n : nat) : list nat :=
  match fuel with
  | 0 => [0]
  | S fuel' =>
    let q := Nat.div n 10 in
    let d := Nat.modulo n 10 in
    if Nat.ltb q 1
    then [d]
    else nat_digit_list_aux fuel' q ++ [d]
  end.

(** Convert a natural number to its list of decimal digits
    (most significant digit first). *)
Definition nat_digit_list (n : nat) : list nat :=
  nat_digit_list_aux n n.

(** * SDL2 types

    Opaque handle types wrapping SDL2 pointers. *)

(** An opaque SDL window handle. Extracted to [SDL_Window*]. *)
Axiom sdl_window : Type.

(** An opaque SDL renderer handle. Extracted to [SDL_Renderer*]. *)
Axiom sdl_renderer : Type.

(** An opaque SDL texture handle. Extracted to [SDL_Texture*]. *)
Axiom sdl_texture : Type.

(** * SDL2 IO operations

    Raw IO axioms for SDL2 functions, wrapped in the Crane [iIO] monad.
    This module is skipped during extraction; the public IO wrappers
    below are what gets extracted. *)

Module SDL_axioms.
  Import IO_axioms.
  (** Create a window with the given title, width, and height. *)
  Axiom icreate_window : PrimString.string -> nat -> nat -> iIO sdl_window.
  (** Create a hardware-accelerated renderer for a window. *)
  Axiom icreate_renderer : sdl_window -> iIO sdl_renderer.
  (** Destroy the renderer and window, then quit SDL. *)
  Axiom idestroy : sdl_renderer -> sdl_window -> iIO void.
  (** Set the current draw color (RGB, alpha is always 255). *)
  Axiom iset_draw_color : sdl_renderer -> nat -> nat -> nat -> iIO void.
  (** Clear the renderer with the current draw color. *)
  Axiom iclear : sdl_renderer -> iIO void.
  (** Present the renderer (flip the back-buffer to screen). *)
  Axiom ipresent : sdl_renderer -> iIO void.
  (** Fill a rectangle at (x, y) with dimensions (w, h). *)
  Axiom ifill_rect : sdl_renderer -> nat -> nat -> nat -> nat -> iIO void.
  (** Draw a single pixel at (x, y). *)
  Axiom idraw_point : sdl_renderer -> nat -> nat -> iIO void.
  (** Poll for an event. Returns an event code as [nat]. *)
  Axiom ipoll_event : iIO nat.
  (** Get the number of milliseconds since SDL was initialized. *)
  Axiom iget_ticks : iIO nat.
  (** Pause execution for the given number of milliseconds. *)
  Axiom idelay : nat -> iIO void.
  (** Load an image file as a texture. *)
  Axiom iload_texture : sdl_renderer -> PrimString.string -> iIO sdl_texture.
  (** Play an audio file asynchronously. *)
  Axiom iplay_sound : PrimString.string -> iIO void.
  (** Render a texture rotated by [angle] degrees, centered at [(cx, cy)],
      optionally flipped horizontally. *)
  Axiom irender_texture_rotated : sdl_renderer -> sdl_texture ->
    nat -> nat -> nat -> nat -> nat -> bool -> iIO void.
End SDL_axioms.

Crane Extract Skip Module SDL_axioms.
Import SDL_axioms.

(** ** Public IO wrappers

    Each wrapper lifts an [iIO] axiom into the [IO] monad via [trigger].
    These are the functions that get extracted to C++ calls. *)

(** Create a window with the given title, width, and height. *)
Definition sdl_create_window (title : PrimString.string) (w h : nat)
  : IO sdl_window :=
  trigger (icreate_window title w h).

(** Create a hardware-accelerated, vsync-enabled renderer. *)
Definition sdl_create_renderer (win : sdl_window) : IO sdl_renderer :=
  trigger (icreate_renderer win).

(** Destroy the renderer and window, then quit SDL. *)
Definition sdl_destroy (ren : sdl_renderer) (win : sdl_window) : IO void :=
  trigger (idestroy ren win).

(** Set the current draw color (RGB, alpha is always 255). *)
Definition sdl_set_draw_color (ren : sdl_renderer) (r g b : nat) : IO void :=
  trigger (iset_draw_color ren r g b).

(** Clear the renderer with the current draw color. *)
Definition sdl_clear (ren : sdl_renderer) : IO void :=
  trigger (iclear ren).

(** Present the renderer (flip the back-buffer to screen). *)
Definition sdl_present (ren : sdl_renderer) : IO void :=
  trigger (ipresent ren).

(** Fill a rectangle at [(x, y)] with dimensions [(w, h)]. *)
Definition sdl_fill_rect (ren : sdl_renderer) (x y w h : nat) : IO void :=
  trigger (ifill_rect ren x y w h).

(** Draw a single pixel at [(x, y)]. *)
Definition sdl_draw_point (ren : sdl_renderer) (x y : nat) : IO void :=
  trigger (idraw_point ren x y).

(** Poll for an event. Returns: 0=none, 1=quit, 2=up, 3=down, 4=left, 5=right. *)
Definition sdl_poll_event : IO nat :=
  trigger ipoll_event.

(** Get the number of milliseconds since SDL was initialized. *)
Definition sdl_get_ticks : IO nat :=
  trigger iget_ticks.

(** Pause execution for the given number of milliseconds. *)
Definition sdl_delay (ms : nat) : IO void :=
  trigger (idelay ms).

(** Load an image file (PNG, SVG, etc.) as a texture via SDL_image. *)
Definition sdl_load_texture (ren : sdl_renderer) (path : PrimString.string)
  : IO sdl_texture :=
  trigger (iload_texture ren path).

(** Play an audio file asynchronously. *)
Definition sdl_play_sound (path : PrimString.string) : IO void :=
  trigger (iplay_sound path).

(** Render a texture centered at [(cx, cy)] with size [(w, h)],
    rotated by [angle] degrees clockwise and optionally mirrored on the y axis. *)
Definition sdl_render_texture_rotated (ren : sdl_renderer) (tex : sdl_texture)
    (cx cy w h angle : nat) (flip_h : bool) : IO void :=
  trigger (irender_texture_rotated ren tex cx cy w h angle flip_h).

(** * Extraction mappings: integer math

    Maps integer math axioms to inline C++ expressions. *)

(** * Extraction mappings: SDL2 types

    Maps opaque SDL types to C++ typedefs defined in [sdl_helpers.h]. *)

Crane Extract Inlined Constant sdl_window => "sdl_window" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_renderer => "sdl_renderer" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_texture => "sdl_texture" From "sdl_helpers.h".

(** * Extraction mappings: SDL2 functions

    Maps each SDL IO wrapper to the corresponding C++ helper
    function in [sdl_helpers.h]. *)

Crane Extract Inlined Constant sdl_create_window =>
  "sdl_create_window(%a0, %a1, %a2)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_create_renderer =>
  "sdl_create_renderer(%a0)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_destroy =>
  "sdl_destroy(%a0, %a1)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_set_draw_color =>
  "sdl_set_draw_color(%a0, %a1, %a2, %a3)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_clear =>
  "sdl_clear(%a0)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_present =>
  "sdl_present(%a0)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_fill_rect =>
  "sdl_fill_rect(%a0, %a1, %a2, %a3, %a4)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_draw_point =>
  "sdl_draw_point(%a0, %a1, %a2)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_poll_event =>
  "sdl_poll_event()" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_get_ticks =>
  "sdl_get_ticks()" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_delay =>
  "sdl_delay(%a0)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_load_texture =>
  "sdl_load_texture(%a0, %a1)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_play_sound =>
  "sdl_play_sound(%a0)" From "sdl_helpers.h".
Crane Extract Inlined Constant sdl_render_texture_rotated =>
  "sdl_render_texture_rotated(%a0, %a1, %a2, %a3, %a4, %a5, %a6, %a7)"
  From "sdl_helpers.h".
