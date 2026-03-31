(** * Rocqman game logic and rendering.

    All game state, logic, ghost_state AI, collision detection, sprite
    rendering, and frame processing are defined here in pure Rocq.
    Extracted to C++ via Crane; the C++ side is a minimal main loop.

    Usage: [From RocqmanGame Require Import Rocqman.] *)

From Corelib Require Import PrimString.
From Stdlib Require Import Lists.List.
Import ListNotations.
From Stdlib Require Import Bool.
From Stdlib Require Import Reals Rtrigo Ratan.
From Crane Require Import Mapping.NatIntStd.
From Crane Require Import Mapping.Std Mapping.Real Monads.ITree Monads.IO.
From Crane Require Extraction.
From RocqmanGame Require Import SDL.

Local Open Scope pstring_scope.

Module Rocqman.

Import IO_axioms.
Import MonadNotations.

(** Two-argument arctangent with the conventional range [-pi, pi]. *)
Definition real_atan2 (y x : R) : R :=
  if Rlt_dec R0 x then atan (Rdiv y x)
  else if Rlt_dec x R0 then
         if Rle_dec R0 y then Rplus (atan (Rdiv y x)) PI
         else Rminus (atan (Rdiv y x)) PI
       else if Rlt_dec R0 y then Rdiv PI (INR 2)
       else if Rlt_dec y R0 then Ropp (Rdiv PI (INR 2))
       else R0.

(** * Types *)

(** A cell on the game board. *)
Inductive cell : Type := Wall | Empty | Dot | PowerPellet.

(** Movement direction for Rocqman and ghosts. *)
Inductive direction : Type := Up | Down | Left | Right | DirNone.

(** ghost_state behavior mode. *)
Inductive ghost_mode : Type := Chase | Frightened.

(** Game phase for screen transitions. *)
Inductive phase : Type := Playing | DeathPause | GameOverScreen | WinScreen.

(** A row/column position on the board. *)
Record position : Type := mkPos { prow : nat; pcol : nat }.

(** A ghost_state with its position, direction, and behavior mode. *)
Record ghost_state : Type := mkGhost {
  gpos : position;
  gdir : direction;
  gmode : ghost_mode
}.

(** The complete game state. *)
Record game_state : Type := mkState {
  board : list (list cell);
  pacpos : position;
  pacdir : direction;
  ghosts : list ghost_state;
  score : nat;
  lives : nat;
  dots_left : nat;
  power_timer : nat;   (** Ticks remaining in power pellet mode. *)
  game_over : bool;
  game_won : bool
}.

(** * Constants *)

(** Number of rows in the board. *)
Definition board_height : nat := 15.
(** Number of columns in the board. *)
Definition board_width : nat := 19.
(** Side length of each cell in pixels. *)
Definition cell_size : nat := 32.
(** Height of the score/lives bar below the board, in pixels. *)
Definition status_height : nat := 40.
(** Total window width in pixels. *)
Definition win_width : nat := board_width * cell_size.
(** Total window height in pixels (board + status bar). *)
Definition win_height : nat := board_height * cell_size + status_height.
(** Milliseconds between game logic ticks. *)
Definition tick_ms : nat := 400.
(** Target milliseconds per render frame (~60 fps). *)
Definition frame_ms : nat := 16.

(** * Board layout

    A 15x19 simplified Rocqman maze.
    Abbreviations [W], [E], [D], [P] are local for readability. *)

Local Definition W := Wall.
Local Definition E := Empty.
Local Definition D := Dot.
Local Definition P := PowerPellet.

(** The hardcoded initial board layout. *)
Definition initial_board : list (list cell) :=
  [ [W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W]
  ; [W;D;D;D;D;D;D;D;D;W;D;D;D;D;D;D;D;D;W]
  ; [W;D;W;W;D;W;W;W;D;W;D;W;W;W;D;W;W;D;W]
  ; [W;P;W;D;D;D;W;D;D;D;D;D;W;D;D;D;W;P;W]
  ; [W;D;W;W;W;D;W;D;W;W;W;D;W;D;W;W;W;D;W]
  ; [W;D;D;D;D;D;D;D;D;D;D;D;D;D;D;D;D;D;W]
  ; [W;W;D;W;D;W;W;D;W;W;W;D;W;W;D;W;D;W;W]
  ; [W;D;D;D;D;W;D;D;D;W;D;D;D;W;D;D;D;D;W]
  ; [W;D;W;W;D;W;W;W;D;W;D;W;W;W;D;W;W;D;W]
  ; [W;D;D;D;D;D;D;D;D;D;D;D;D;D;D;D;D;D;W]
  ; [W;D;W;W;W;D;W;D;W;W;W;D;W;D;W;W;W;D;W]
  ; [W;P;W;D;D;D;W;D;D;D;D;D;W;D;D;D;W;P;W]
  ; [W;D;W;W;D;W;W;W;D;W;D;W;W;W;D;W;W;D;W]
  ; [W;D;D;D;D;D;D;D;D;W;D;D;D;D;D;D;D;D;W]
  ; [W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W;W]
  ].

(** * Helper functions *)

(** Count dots and power pellets in a single row. *)
Fixpoint count_row (r : list cell) : nat :=
  match r with
  | [] => 0
  | Dot :: rest => 1 + count_row rest
  | PowerPellet :: rest => 1 + count_row rest
  | _ :: rest => count_row rest
  end.

(** Count total collectible items on the board. *)
Fixpoint count_dots (b : list (list cell)) : nat :=
  match b with
  | [] => 0
  | row :: rest => count_row row + count_dots rest
  end.

(** Look up the cell at [(row, col)]. Returns [Wall] for out-of-bounds. *)
Definition get_cell (row col : nat) (b : list (list cell)) : cell :=
  nth col (nth row b []) Wall.

(** Replace the [n]-th element of a list. *)
Fixpoint replace_nth {A : Type} (n : nat) (l : list A) (x : A) : list A :=
  match l with
  | [] => []
  | h :: t => match n with
              | 0 => x :: t
              | S n' => h :: replace_nth n' t x
              end
  end.

(** Set the cell at [(row, col)] to [c]. *)
Definition set_cell (row col : nat) (c : cell) (b : list (list cell))
  : list (list cell) :=
  let r := nth row b [] in
  replace_nth row b (replace_nth col r c).

(** Check whether the cell at [(row, col)] is a wall. *)
Definition is_wall (row col : nat) (b : list (list cell)) : bool :=
  match get_cell row col b with
  | Wall => true
  | _ => false
  end.

(** Move a position one step in the given direction. *)
Definition move_pos (d : direction) (p : position) : position :=
  match d with
  | Up    => mkPos (Nat.pred (prow p)) (pcol p)
  | Down  => mkPos (S (prow p)) (pcol p)
  | Left  => mkPos (prow p) (Nat.pred (pcol p))
  | Right => mkPos (prow p) (S (pcol p))
  | DirNone => p
  end.

(** Check whether moving in direction [d] from position [p] is possible. *)
Definition can_move (d : direction) (p : position) (b : list (list cell))
  : bool :=
  let new_p := move_pos d p in
  negb (is_wall (prow new_p) (pcol new_p) b).

(** * Game logic *)

(** Set all ghosts to [Frightened] or [Chase] mode. *)
Fixpoint update_ghost_modes (gs : list ghost_state) (powered : bool) : list ghost_state :=
  match gs with
  | [] => []
  | g :: rest =>
    let mode := if powered then Frightened else Chase in
    mkGhost (gpos g) (gdir g) mode :: update_ghost_modes rest powered
  end.

(** Set Rocqman's direction if the move is valid. *)
Definition set_direction (d : direction) (gs : game_state) : game_state :=
  if can_move d (pacpos gs) (board gs)
  then mkState (board gs) (pacpos gs) d (ghosts gs) (score gs) (lives gs)
               (dots_left gs) (power_timer gs) (game_over gs) (game_won gs)
  else gs.

(** Move Rocqman one step, eating dots/pellets and updating score. *)
Definition move_pacman (gs : game_state) : game_state :=
  if game_over gs || game_won gs then gs
  else
    let new_pos := move_pos (pacdir gs) (pacpos gs) in
    if is_wall (prow new_pos) (pcol new_pos) (board gs) then gs
    else
      let cell := get_cell (prow new_pos) (pcol new_pos) (board gs) in
      let new_board := match cell with
                       | Dot | PowerPellet =>
                         set_cell (prow new_pos) (pcol new_pos) Empty (board gs)
                       | _ => board gs
                       end in
      let add_score := match cell with
                       | Dot => 10
                       | PowerPellet => 50
                       | _ => 0
                       end in
      let new_dots := match cell with
                      | Dot | PowerPellet => Nat.pred (dots_left gs)
                      | _ => dots_left gs
                      end in
      let new_power := match cell with
                       | PowerPellet => 20
                       | _ => power_timer gs
                       end in
      let new_ghosts := match cell with
                        | PowerPellet =>
                          update_ghost_modes (ghosts gs) true
                        | _ => ghosts gs
                        end in
      let won := Nat.eqb new_dots 0 in
      mkState new_board new_pos (pacdir gs) new_ghosts
              (score gs + add_score) (lives gs)
              new_dots new_power won won.

(** * ghost_state AI

    Ghosts use a greedy Manhattan-distance heuristic:
    at each step they pick the direction (excluding reversal)
    that minimizes distance to their target. In [Chase] mode
    the target is Rocqman; in [Frightened] mode it is (0,0). *)

(** Absolute difference of two natural numbers. *)
Definition abs_diff (a b : nat) : nat :=
  if Nat.leb a b then b - a else a - b.

(** Manhattan distance between two positions. *)
Definition manhattan (p1 p2 : position) : nat :=
  abs_diff (prow p1) (prow p2) + abs_diff (pcol p1) (pcol p2).

(** Check whether two directions are opposite (ghosts cannot reverse). *)
Definition is_opposite (d1 d2 : direction) : bool :=
  match d1, d2 with
  | Up, Down | Down, Up | Left, Right | Right, Left => true
  | _, _ => false
  end.

(** Try direction [d] for ghost_state [g]: if it improves on the current
    best distance to [target], return it as the new best. *)
Definition try_dir (d : direction) (g : ghost_state) (target : position)
                   (b : list (list cell))
                   (best_d : direction) (best_dist : nat)
  : direction * nat :=
  if negb (can_move d (gpos g) b) then (best_d, best_dist)
  else if is_opposite d (gdir g) then (best_d, best_dist)
  else
    let new_pos := move_pos d (gpos g) in
    let dist := manhattan new_pos target in
    if Nat.ltb dist best_dist then (d, dist) else (best_d, best_dist).

(** Choose the best direction for a ghost_state by trying all four directions. *)
Definition choose_ghost_dir (g : ghost_state) (target : position)
                            (b : list (list cell)) : direction :=
  let '(d1, dist1) := try_dir Up    g target b DirNone 999 in
  let '(d2, dist2) := try_dir Down  g target b d1 dist1 in
  let '(d3, dist3) := try_dir Left  g target b d2 dist2 in
  let '(d4, _)     := try_dir Right g target b d3 dist3 in
  d4.

(** Move a single ghost_state one step toward its target. *)
Definition move_one_ghost (g : ghost_state) (pac : position)
                          (b : list (list cell)) : ghost_state :=
  let target := match gmode g with
                | Chase => pac
                | Frightened => mkPos 0 0
                end in
  let dir := choose_ghost_dir g target b in
  if can_move dir (gpos g) b
  then mkGhost (move_pos dir (gpos g)) dir (gmode g)
  else g.

(** Move all ghosts one step. *)
Fixpoint move_ghosts_list (gs : list ghost_state) (pac : position)
                          (b : list (list cell)) : list ghost_state :=
  match gs with
  | [] => []
  | g :: rest => move_one_ghost g pac b :: move_ghosts_list rest pac b
  end.

(** Advance all ghosts in the game state by one step. *)
Definition move_ghosts (gs : game_state) : game_state :=
  mkState (board gs) (pacpos gs) (pacdir gs)
          (move_ghosts_list (ghosts gs) (pacpos gs) (board gs))
          (score gs) (lives gs) (dots_left gs) (power_timer gs)
          (game_over gs) (game_won gs).

(** * Collision detection *)

(** Find a ghost_state occupying the given position, if any. *)
Fixpoint ghost_at_pos (row col : nat) (gs : list ghost_state) : option ghost_state :=
  match gs with
  | [] => None
  | g :: rest =>
    if Nat.eqb (prow (gpos g)) row && Nat.eqb (pcol (gpos g)) col
    then Some g
    else ghost_at_pos row col rest
  end.

(** Return a ghost_state to its spawn point at the center of the board. *)
Definition respawn_ghost (g : ghost_state) : ghost_state :=
  mkGhost (mkPos 7 9) DirNone Chase.

(** Handle Rocqman-ghost_state collisions: eat frightened ghosts for
    200 points, or lose a life when touching a chasing ghost_state. *)
Definition check_collisions (gs : game_state) : game_state :=
  match ghost_at_pos (prow (pacpos gs)) (pcol (pacpos gs)) (ghosts gs) with
  | None => gs
  | Some g =>
    match gmode g with
    | Frightened =>
      let new_ghosts := map (fun g' =>
        if Nat.eqb (prow (gpos g')) (prow (pacpos gs)) &&
           Nat.eqb (pcol (gpos g')) (pcol (pacpos gs))
        then respawn_ghost g'
        else g') (ghosts gs) in
      mkState (board gs) (pacpos gs) (pacdir gs) new_ghosts
              (score gs + 200) (lives gs) (dots_left gs) (power_timer gs)
              (game_over gs) (game_won gs)
    | Chase =>
      let new_lives := Nat.pred (lives gs) in
      let dead := Nat.eqb new_lives 0 in
      mkState (board gs) (mkPos 9 9) DirNone (ghosts gs)
              (score gs) new_lives (dots_left gs) 0
              dead (game_won gs)
    end
  end.

(** Decrement the power pellet timer and update ghost_state modes. *)
Definition tick_power (gs : game_state) : game_state :=
  match power_timer gs with
  | 0 => gs
  | S n =>
    let powered := negb (Nat.eqb n 0) in
    let new_ghosts := update_ghost_modes (ghosts gs) powered in
    mkState (board gs) (pacpos gs) (pacdir gs) new_ghosts
            (score gs) (lives gs) (dots_left gs) n
            (game_over gs) (game_won gs)
  end.

(** * Main tick *)

(** Advance the game by one logical step: move Rocqman, move ghosts,
    and tick the power timer. Collision is handled per-frame at the
    pixel level in [process_frame]. *)
Definition tick (gs : game_state) : game_state :=
  if game_over gs || game_won gs then gs
  else
    let gs1 := move_pacman gs in
    let gs2 := move_ghosts gs1 in
    tick_power gs2.

(** * Initial state *)

(** The four ghosts, starting in the board corners. *)
Definition initial_ghosts : list ghost_state :=
  [ mkGhost (mkPos 1 1) DirNone Chase
  ; mkGhost (mkPos 1 17) DirNone Chase
  ; mkGhost (mkPos 13 1) DirNone Chase
  ; mkGhost (mkPos 13 17) DirNone Chase
  ].

(** The starting game state: Rocqman at center, 3 lives, all dots placed. *)
Definition initial_state : game_state :=
  let b := set_cell 9 9 Empty initial_board in
  mkState b
          (mkPos 9 9)
          DirNone
          initial_ghosts
          0
          3
          (count_dots b)
          0
          false
          false.

(** * Drawing primitives

    Low-level shape drawing built on [sdl_fill_rect] and [sdl_draw_point].
    Used by the sprite rendering functions below. *)

(** Draw a filled circle row by row, computing the half-width at
    each scanline via integer square root. *)
Fixpoint filled_circle_rows (ren : sdl_renderer) (cx base_y : nat)
                            (radius i count : nat) : IO void :=
  match count with
  | 0 => Ret ghost
  | S count' =>
    let dist := abs_diff i radius in
    let d2 := dist * dist in
    let r2 := radius * radius in
    (if Nat.leb d2 r2 then
       let half := Nat.sqrt (r2 - d2) in
       sdl_fill_rect ren (cx - half) (base_y + i) (half + half + 1) 1
     else Ret ghost) ;;
    filled_circle_rows ren cx base_y radius (S i) count'
  end.

(** Draw a filled circle centered at [(cx, cy)] with the given radius. *)
Definition draw_filled_circle (ren : sdl_renderer) (cx cy radius : nat)
  : IO void :=
  filled_circle_rows ren cx (cy - radius) radius 0 (radius + radius + 1).

(** Draw the top half of a circle (used for the ghost_state head). *)
Fixpoint semicircle_top_rows (ren : sdl_renderer) (cx base_y : nat)
                             (radius i count : nat) : IO void :=
  match count with
  | 0 => Ret ghost
  | S count' =>
    let dist := radius - i in  (* i goes 0..radius, dist goes radius..0 *)
    let half := Nat.sqrt (radius * radius - dist * dist) in
    sdl_fill_rect ren (cx - half) (base_y + i) (half + half + 1) 1 ;;
    semicircle_top_rows ren cx base_y radius (S i) count'
  end.

(** Draw a top semicircle centered at [(cx, cy)]. *)
Definition draw_top_semicircle (ren : sdl_renderer) (cx cy radius : nat)
  : IO void :=
  semicircle_top_rows ren cx (cy - radius) radius 0 (radius + 1).

(** * ghost_state sprite rendering

    Each ghost_state is composed of a semicircle head, a rectangular body,
    three scalloped "feet", and a pair of eyes with pupils. *)

(** Map a color index to an RGB triple: 0=red, 1=pink, 2=cyan,
    3=orange, 4+=frightened blue. *)
Definition ghost_body_color (color_idx : nat)
  : (nat * nat * nat) :=
  match color_idx with
  | 0 => (255, 0, 0)      (* red *)
  | 1 => (255, 184, 222)  (* pink *)
  | 2 => (0, 255, 255)    (* cyan *)
  | 3 => (255, 184, 82)   (* orange *)
  | _ => (33, 33, 222)    (* frightened blue *)
  end.

(** Draw the ghost_state body: semicircle head, rectangular torso,
    and three scalloped bumps at the bottom. *)
Definition draw_ghost_body (ren : sdl_renderer) (cx cy : nat)
                           (radius : nat) (cr cg cb : nat) : IO void :=
  sdl_set_draw_color ren cr cg cb ;;
  draw_top_semicircle ren cx cy radius ;;
  sdl_fill_rect ren (cx - radius) cy (radius + radius + 1) radius ;;
  let seg := Nat.div (radius + radius) 3 in
  let sr := Nat.div seg 2 in
  let bx0 := cx - radius + Nat.div seg 2 in
  draw_filled_circle ren bx0 (cy + radius) sr ;;
  draw_filled_circle ren (bx0 + seg) (cy + radius) sr ;;
  draw_filled_circle ren (bx0 + seg + seg) (cy + radius) sr.

(** Draw the ghost_state's eyes: white sclera and blue pupils. *)
Definition draw_ghost_eyes (ren : sdl_renderer) (cx cy : nat)
                           (radius : nat) : IO void :=
  let eye_offset := Nat.div radius 3 in
  sdl_set_draw_color ren 255 255 255 ;;
  draw_filled_circle ren (cx - eye_offset) (cy - 2) 4 ;;
  draw_filled_circle ren (cx + eye_offset) (cy - 2) 4 ;;
  sdl_set_draw_color ren 33 33 222 ;;
  draw_filled_circle ren (cx - eye_offset + 1) (cy - 1) 2 ;;
  draw_filled_circle ren (cx + eye_offset + 1) (cy - 1) 2.

(** Draw a white ⊥ symbol on the ghost_state's body. *)
Definition draw_ghost_bottom (ren : sdl_renderer)
                             (cx cy : nat) : IO void :=
  sdl_set_draw_color ren 255 255 255 ;;
  (* Vertical bar *)
  sdl_fill_rect ren (cx - 1) (cy - 7) 3 11 ;;
  (* Horizontal bar *)
  sdl_fill_rect ren (cx - 6) (cy + 2) 13 3.

(** Draw a complete ghost_state sprite with a ⊥ symbol on its body. *)
Definition draw_ghost_sprite (ren : sdl_renderer)
                             (px py color_idx : nat) : IO void :=
  let radius := 13 in
  let '(cr, cg, cb) := ghost_body_color color_idx in
  draw_ghost_body ren px py radius cr cg cb ;;
  draw_ghost_bottom ren px py.

(** * Rocqman sprite rendering

    Rocqman is drawn pixel-by-pixel: each pixel inside the circle is
    tested against the mouth opening angle using [real_atan2]. The
    mouth animates via a sine wave over time. *)

(** Draw one row of pixels for the Rocqman sprite, skipping pixels
    inside the mouth wedge. *)
Fixpoint pac_row_pixels (ren : sdl_renderer)
                        (sx sy_row : nat) (radius : nat)
                        (fdy dir_ang mouth : R)
                        (dy_sq r2 : nat) (dx count : nat) : IO void :=
  match count with
  | 0 => Ret ghost
  | S count' =>
    let dx_off := abs_diff dx radius in
    let dist_sq := dx_off * dx_off + dy_sq in
    (if Nat.leb dist_sq r2 then
       let fdx := Rminus (INR dx) (INR radius) in
       let ang := real_atan2 fdy fdx in
       let rel0 := Rminus ang dir_ang in
       let rel1 := if Rlt_dec PI rel0
                   then Rminus rel0 (PI + PI) else rel0 in
       let rel := if Rlt_dec rel1 (Ropp PI)
                  then Rplus rel1 (PI + PI) else rel1 in
       if Rlt_dec (Rabs rel) mouth
       then Ret ghost
       else sdl_draw_point ren (sx + dx) sy_row
     else Ret ghost) ;;
    pac_row_pixels ren sx sy_row radius fdy dir_ang mouth dy_sq r2 (S dx) count'
  end.

(** Iterate over all rows of the Rocqman sprite bounding box. *)
Fixpoint pac_rows (ren : sdl_renderer) (sx base_y : nat) (radius : nat)
                  (dir_ang mouth : R) (r2 diameter : nat)
                  (dy count : nat) : IO void :=
  match count with
  | 0 => Ret ghost
  | S count' =>
    let dy_off := abs_diff dy radius in
    let dy_sq := dy_off * dy_off in
    let fdy := Rminus (INR dy) (INR radius) in
    pac_row_pixels ren sx (base_y + dy) radius fdy dir_ang mouth
                   dy_sq r2 0 diameter ;;
    pac_rows ren sx base_y radius dir_ang mouth r2 diameter (S dy) count'
  end.

(** Convert a direction index to a facing angle in radians.
    0=right, 1=left, 2=up, 3=down. *)
Definition dir_angle (dir : nat) : R :=
  match dir with
  | 0 => INR 0
  | 1 => PI
  | 2 => Ropp (PI / INR 2)
  | 3 => PI / INR 2
  | _ => INR 0
  end.

(** Compute the mouth opening half-angle from the current time,
    producing a smooth chomp animation via a sine wave. *)
Definition compute_mouth_angle (time_ms : nat) : R :=
  let ftime := INR time_ms in
  let phase := Rdiv ftime (INR 1000) in
  let arg := Rmult (Rmult phase (INR 8)) PI in
  let s := Rabs (sin arg) in
  let f015 := Rdiv (INR 15) (INR 100) in
  let f035 := Rdiv (INR 35) (INR 100) in
  Rplus f015 (Rmult f035 s).

(** Draw the complete Rocqman sprite at pixel position [(px, py)]
    facing direction [dir] with mouth animation based on [time_ms]. *)
Definition draw_pacman_sprite (ren : sdl_renderer)
                              (px py dir time_ms : nat) : IO void :=
  let radius := 14 in
  let diameter := radius + radius + 1 in
  let r2 := radius * radius in
  let dir_a := dir_angle dir in
  let mouth := compute_mouth_angle time_ms in
  sdl_set_draw_color ren 255 255 0 ;;
  pac_rows ren (px - radius) (py - radius) radius dir_a mouth
           r2 diameter 0 diameter.

(** * Bitmap font

    A 5x7 bitmap font covering digits 0-9, space, and letters A-Z.
    Glyph indices: 0-9 = digits, 10 = space, 11-36 = A-Z.
    Each glyph is stored as 7 rows of 5-bit bitmasks. *)

(** Look up one row of bitmap data for glyph [g]. *)
Definition glyph_row_data (g row : nat) : nat :=
  nth row (nth g
    [ (* 0 *) [14;17;19;21;25;17;14]
    ; (* 1 *) [4;12;4;4;4;4;14]
    ; (* 2 *) [14;17;1;6;8;16;31]
    ; (* 3 *) [14;17;1;6;1;17;14]
    ; (* 4 *) [2;6;10;18;31;2;2]
    ; (* 5 *) [31;16;30;1;1;17;14]
    ; (* 6 *) [6;8;16;30;17;17;14]
    ; (* 7 *) [31;1;2;4;8;8;8]
    ; (* 8 *) [14;17;17;14;17;17;14]
    ; (* 9 *) [14;17;17;15;1;2;12]
    ; (* 10 = space *) [0;0;0;0;0;0;0]
    ; (* 11 = A *) [4;10;17;17;31;17;17]
    ; (* 12 = B *) [30;17;17;30;17;17;30]
    ; (* 13 = C *) [14;17;16;16;16;17;14]
    ; (* 14 = D *) [28;18;17;17;17;18;28]
    ; (* 15 = E *) [31;16;16;30;16;16;31]
    ; (* 16 = F *) [31;16;16;30;16;16;16]
    ; (* 17 = G *) [14;17;16;23;17;17;14]
    ; (* 18 = H *) [17;17;17;31;17;17;17]
    ; (* 19 = I *) [14;4;4;4;4;4;14]
    ; (* 20 = J *) [7;2;2;2;2;18;12]
    ; (* 21 = K *) [17;18;20;24;20;18;17]
    ; (* 22 = L *) [16;16;16;16;16;16;31]
    ; (* 23 = M *) [17;27;21;17;17;17;17]
    ; (* 24 = N *) [17;25;21;19;17;17;17]
    ; (* 25 = O *) [14;17;17;17;17;17;14]
    ; (* 26 = P *) [30;17;17;30;16;16;16]
    ; (* 27 = Q *) [14;17;17;17;21;18;13]
    ; (* 28 = R *) [30;17;17;30;20;18;17]
    ; (* 29 = S *) [14;17;16;14;1;17;14]
    ; (* 30 = T *) [31;4;4;4;4;4;4]
    ; (* 31 = U *) [17;17;17;17;17;17;14]
    ; (* 32 = V *) [17;17;17;17;10;10;4]
    ; (* 33 = W *) [17;17;17;21;21;21;10]
    ; (* 34 = X *) [17;17;10;4;10;17;17]
    ; (* 35 = Y *) [17;17;10;4;4;4;4]
    ; (* 36 = Z *) [31;1;2;4;8;16;31]
    ] []) 0.

(** Draw one row of a glyph at pixel scale [s]. *)
Fixpoint draw_glyph_row (ren : sdl_renderer)
                         (sx sy : nat) (row_bits : nat)
                         (dx count s : nat) : IO void :=
  match count with
  | 0 => Ret ghost
  | S count' =>
    (if nat_testbit row_bits (4 - dx) then
       sdl_fill_rect ren (sx + dx * s) sy s s
     else Ret ghost) ;;
    draw_glyph_row ren sx sy row_bits (S dx) count' s
  end.

(** Draw all 7 rows of a glyph [g] at scale [s]. *)
Fixpoint draw_glyph_rows (ren : sdl_renderer) (sx sy g : nat)
                          (row count s : nat) : IO void :=
  match count with
  | 0 => Ret ghost
  | S count' =>
    let bits := glyph_row_data g row in
    draw_glyph_row ren sx (sy + row * s) bits 0 5 s ;;
    draw_glyph_rows ren sx sy g (S row) count' s
  end.

(** Draw a single glyph [g] at [(sx, sy)] with pixel scale [s]. *)
Definition draw_one_glyph (ren : sdl_renderer) (sx sy g s : nat) : IO void :=
  draw_glyph_rows ren sx sy g 0 7 s.

(** Draw a list of glyphs left to right at scale [s]. *)
Fixpoint draw_glyphs (ren : sdl_renderer) (sx sy s : nat)
                      (glyphs : list nat) : IO void :=
  match glyphs with
  | [] => Ret ghost
  | g :: rest =>
    draw_one_glyph ren sx sy g s ;;
    draw_glyphs ren (sx + 6 * s) sy s rest
  end.

(** Draw a list of digit glyphs at scale 3 (for score display). *)
Fixpoint draw_number_digits (ren : sdl_renderer) (sx sy : nat)
                            (digits : list nat) : IO void :=
  match digits with
  | [] => Ret ghost
  | d :: rest =>
    draw_one_glyph ren sx sy d 3 ;;
    draw_number_digits ren (sx + 18) sy rest
  end.

(** Draw a natural number as white bitmap digits at [(sx, sy)]. *)
Definition draw_number_sprite (ren : sdl_renderer) (n sx sy : nat) : IO void :=
  sdl_set_draw_color ren 255 255 255 ;;
  draw_number_digits ren sx sy (nat_digit_list n).

(** * Arcade text messages

    Glyph indices: 0-9 = digits, 10 = space, 11 = A, ... 36 = Z. *)

(** "GAME OVER" *)
Definition msg_game_over : list nat :=
  [17;11;23;15;10;25;32;15;28].

(** "YOU WIN" *)
Definition msg_you_win : list nat :=
  [35;25;31;10;33;19;24].

(** "N LIVES LEFT" — prepends the digit for the lives count. *)
Definition msg_lives_left (n : nat) : list nat :=
  nat_digit_list n ++ [10;22;19;32;15;29;10;22;15;16;30].

(** Draw centered arcade text on a black screen. *)
Definition draw_message_screen (ren : sdl_renderer) (msg : list nat)
  : IO void :=
  let s := 4 in
  let glyph_w := 6 * s in
  let text_w := length msg * glyph_w in
  let sx := Nat.div (win_width - text_w) 2 in
  let sy := Nat.div win_height 2 - Nat.div (7 * s) 2 in
  sdl_set_draw_color ren 0 0 0 ;;
  sdl_clear ren ;;
  sdl_set_draw_color ren 255 255 255 ;;
  draw_glyphs ren sx sy s msg ;;
  sdl_present ren.

(** * Life icon *)

(** Draw a small red heart representing one remaining life. *)
Definition draw_life_icon (ren : sdl_renderer) (x y : nat) : IO void :=
  sdl_set_draw_color ren 150 10 35 ;;
  sdl_fill_rect ren (x - 9) (y - 6) 6 6 ;;
  sdl_fill_rect ren (x + 3) (y - 6) 6 6 ;;
  sdl_fill_rect ren (x - 11) y 22 6 ;;
  sdl_fill_rect ren (x - 7) (y + 6) 14 4 ;;
  sdl_fill_rect ren (x - 5) (y + 10) 10 4 ;;
  sdl_fill_rect ren (x - 3) (y + 14) 6 3 ;;
  sdl_fill_rect ren (x - 1) (y + 17) 2 2 ;;
  sdl_set_draw_color ren 230 45 85 ;;
  sdl_fill_rect ren (x - 7) (y - 5) 4 4 ;;
  sdl_fill_rect ren (x + 3) (y - 5) 4 4 ;;
  sdl_fill_rect ren (x - 8) (y - 1) 16 5 ;;
  sdl_fill_rect ren (x - 5) (y + 4) 10 4 ;;
  sdl_fill_rect ren (x - 3) (y + 8) 6 4 ;;
  sdl_set_draw_color ren 255 170 190 ;;
  sdl_fill_rect ren (x - 5) (y - 4) 2 2 ;;
  sdl_fill_rect ren (x + 3) (y - 4) 2 2.

(** * Pixel coordinate helpers

    Convert between board grid coordinates and pixel positions. *)

(** Half a cell side, used for centering sprites. *)
Definition half_cell : nat := 16.

(** Pixel x-coordinate of a cell's center. *)
Definition cell_center_x (col : nat) : nat :=
  col * cell_size + half_cell.

(** Pixel y-coordinate of a cell's center. *)
Definition cell_center_y (row : nat) : nat :=
  row * cell_size + half_cell.

(** Linear interpolation between [from_v] and [to_v] at fraction
    [num/den]. Used for smooth inter-tick sprite movement. *)
Definition lerp (from_v to_v num den : nat) : nat :=
  if Nat.leb den 0 then to_v
  else
    if Nat.leb from_v to_v
    then from_v + Nat.div ((to_v - from_v) * num) den
    else from_v - Nat.div ((from_v - to_v) * num) den.

(** Convert a [direction] to the numeric index used by [dir_angle]. *)
Definition dir_to_nat (d : direction) : nat :=
  match d with
  | Right => 0
  | Left => 1
  | Up => 2
  | Down => 3
  | DirNone => 0
  end.

(** Map a ghost_state index and mode to a color index for [ghost_body_color].
    Frightened ghosts always use index 4 (blue). *)
Definition ghost_color_index (idx : nat) (gm : ghost_mode) : nat :=
  match gm with
  | Frightened => 4
  | Chase => idx
  end.

(** * SDL rendering functions

    These functions compose the drawing primitives above to render
    the full game frame: board cells, sprites, and the status bar. *)

(** Draw a small green checkmark for power pellets. *)
Definition draw_dot_check (ren : sdl_renderer) (cx cy : nat) : IO void :=
  sdl_set_draw_color ren 60 200 90 ;;
  sdl_fill_rect ren (cx - 6) (cy + 1) 3 3 ;;
  sdl_fill_rect ren (cx - 3) (cy + 4) 3 3 ;;
  sdl_fill_rect ren cx (cy + 1) 3 3 ;;
  sdl_fill_rect ren (cx + 3) (cy - 2) 3 3.

(** Draw one row of board cells: walls as blue rectangles, dots as
    small white circles, power pellets as green checkmarks. *)
Fixpoint draw_row_cells (ren : sdl_renderer) (row col : nat)
                        (cells : list cell) (pellet_phase : nat) : IO void :=
  match cells with
  | [] => Ret ghost
  | c :: rest =>
    (match c with
     | Wall =>
       sdl_set_draw_color ren 33 33 222 ;;
       sdl_fill_rect ren (col * cell_size + 1) (row * cell_size + 1)
                     (cell_size - 2) (cell_size - 2)
     | Dot =>
       sdl_set_draw_color ren 255 255 255 ;;
       draw_filled_circle ren (cell_center_x col) (cell_center_y row) 2
     | PowerPellet =>
       draw_dot_check ren (cell_center_x col) (cell_center_y row)
     | Empty => Ret ghost
     end) ;;
    draw_row_cells ren row (S col) rest pellet_phase
  end.

(** Draw all board rows. *)
Fixpoint draw_board_rows (ren : sdl_renderer) (row : nat)
                         (rows : list (list cell)) (pellet_phase : nat) : IO void :=
  match rows with
  | [] => Ret ghost
  | cells :: rest =>
    draw_row_cells ren row 0 cells pellet_phase ;;
    draw_board_rows ren (S row) rest pellet_phase
  end.

(** Draw the entire game board. *)
Definition draw_board_sdl (ren : sdl_renderer) (gs : game_state)
                          (pellet_phase : nat) : IO void :=
  draw_board_rows ren 0 (board gs) pellet_phase.

(** Draw all ghosts with smooth interpolation between their previous
    and current positions. *)
Fixpoint draw_ghosts_aux (ren : sdl_renderer) (idx : nat) (gs : list ghost_state)
                         (prev_gs : list ghost_state)
                         (t_num t_den : nat) (time_ms : nat) : IO void :=
  match gs with
  | [] => Ret ghost
  | g :: rest =>
    let prev_g := match prev_gs with
                  | [] => g
                  | pg :: _ => pg
                  end in
    let prev_rest := match prev_gs with
                     | [] => []
                     | _ :: pr => pr
                     end in
    let px := lerp (cell_center_x (pcol (gpos prev_g)))
                   (cell_center_x (pcol (gpos g))) t_num t_den in
    let py := lerp (cell_center_y (prow (gpos prev_g)))
                   (cell_center_y (prow (gpos g))) t_num t_den in
    let col := ghost_color_index (Nat.modulo idx 4) (gmode g) in
    draw_ghost_sprite ren px py col ;;
    draw_ghosts_aux ren (S idx) rest prev_rest t_num t_den time_ms
  end.

(** direction to rotation angle in degrees for texture rendering.
    The Rocq logo faces right by default; left is handled by mirroring. *)
Definition dir_to_degrees (d : direction) : nat :=
  match d with
  | Right   => 0
  | Down    => 90
  | Left    => 0
  | Up      => 270
  | DirNone => 0
  end.

Definition dir_flip_h (d : direction) : bool :=
  match d with
  | Left => true
  | _ => false
  end.

(** Draw the player sprite (Rocq logo) with smooth interpolation
    from [prev_pos], rotated to face the current direction. *)
Definition draw_player_sdl (ren : sdl_renderer) (tex : sdl_texture)
                           (gs : game_state) (prev_pos : position)
                           (t_num t_den : nat) : IO void :=
  let px := lerp (cell_center_x (pcol prev_pos))
                 (cell_center_x (pcol (pacpos gs))) t_num t_den in
  let py := lerp (cell_center_y (prow prev_pos))
                 (cell_center_y (prow (pacpos gs))) t_num t_den in
  sdl_render_texture_rotated ren tex px py 28 28
                             (dir_to_degrees (pacdir gs))
                             (dir_flip_h (pacdir gs)).

(** Draw [n] life icons in the status bar, right-aligned. *)
Fixpoint draw_lives_aux (ren : sdl_renderer) (n : nat) (i : nat) : IO void :=
  match n with
  | 0 => Ret ghost
  | S n' =>
    draw_life_icon ren (win_width - 30 - i * 28)
                   (board_height * cell_size + 8 + 12) ;;
    draw_lives_aux ren n' (S i)
  end.

(** Draw the status bar: score on the left, lives on the right. *)
Definition draw_status_bar (ren : sdl_renderer) (gs : game_state) : IO void :=
  draw_number_sprite ren (score gs) 10 (board_height * cell_size + 8) ;;
  draw_lives_aux ren (lives gs) 0.

(** Render a complete frame: clear screen, draw board, ghosts,
    player sprite, status bar, and present. *)
Definition render_frame (ren : sdl_renderer) (tex : sdl_texture)
                        (gs : game_state)
                        (prev_pac : position) (prev_ghosts : list ghost_state)
                        (t_num t_den : nat) (time_ms : nat) : IO void :=
  sdl_set_draw_color ren 0 0 0 ;;
  sdl_clear ren ;;
  draw_board_sdl ren gs time_ms ;;
  draw_ghosts_aux ren 0 (ghosts gs) prev_ghosts t_num t_den time_ms ;;
  draw_player_sdl ren tex gs prev_pac t_num t_den ;;
  draw_status_bar ren gs ;;
  sdl_present ren.

(** * Event handling *)

(** Map an SDL event code to a quit flag and updated game state.
    Event codes: 1=quit, 2=up, 3=down, 4=left, 5=right, 0/other=none. *)
Definition handle_event (ev : nat) (gs : game_state) : (bool * game_state) :=
  match ev with
  | 1 => (true, gs)
  | 2 => (false, set_direction Up gs)
  | 3 => (false, set_direction Down gs)
  | 4 => (false, set_direction Left gs)
  | 5 => (false, set_direction Right gs)
  | _ => (false, gs)
  end.

(** * Pixel-level collision detection

    Checks distance between interpolated sprite positions every frame,
    giving much more responsive collision than grid-based checks. *)

(** Find the first ghost_state whose interpolated pixel position is within
    [threshold] pixels of the player at [(px, py)]. Returns the
    ghost_state's index and mode. *)
Fixpoint find_pixel_collision (px py : nat) (gs : list ghost_state)
    (prev_gs : list ghost_state) (t_num t_den threshold idx : nat)
    : option (nat * ghost_mode) :=
  match gs with
  | [] => None
  | g :: rest =>
    let prev_g := match prev_gs with [] => g | pg :: _ => pg end in
    let prev_rest := match prev_gs with [] => [] | _ :: pr => pr end in
    let gx := lerp (cell_center_x (pcol (gpos prev_g)))
                   (cell_center_x (pcol (gpos g))) t_num t_den in
    let gy := lerp (cell_center_y (prow (gpos prev_g)))
                   (cell_center_y (prow (gpos g))) t_num t_den in
    let dx := abs_diff px gx in
    let dy := abs_diff py gy in
    if Nat.leb (dx * dx + dy * dy) (threshold * threshold) then
      Some (idx, gmode g)
    else
      find_pixel_collision px py rest prev_rest t_num t_den threshold (S idx)
  end.

(** Eat the ghost_state at index [idx], respawning it and adding 200 points. *)
Definition eat_ghost_idx (idx : nat) (gs : game_state) : game_state :=
  let default_g := mkGhost (mkPos 0 0) DirNone Chase in
  let new_ghosts := replace_nth idx (ghosts gs)
                      (respawn_ghost (nth idx (ghosts gs) default_g)) in
  mkState (board gs) (pacpos gs) (pacdir gs) new_ghosts
          (score gs + 200) (lives gs) (dots_left gs) (power_timer gs)
          (game_over gs) (game_won gs).

(** Lose one life, respawn player at center, reset power timer. *)
Definition lose_one_life (gs : game_state) : game_state :=
  let new_lives := Nat.pred (lives gs) in
  mkState (board gs) (mkPos 9 9) DirNone (ghosts gs)
          (score gs) new_lives (dots_left gs) 0
          (Nat.eqb new_lives 0) (game_won gs).

(** Apply a direction input event to the game state. *)
Definition apply_direction (ev : nat) (gs : game_state) : game_state :=
  match ev with
  | 2 => set_direction Up gs
  | 3 => set_direction Down gs
  | 4 => set_direction Left gs
  | 5 => set_direction Right gs
  | _ => gs
  end.

(** * Game loop state *)

(** Persistent state carried between frames by the C++ main loop. *)
Record loop_state : Type := mkLoop {
  ls_game : game_state;          (** Current game state. *)
  ls_prev_pac : position;       (** Rocqman's position last tick (for lerp). *)
  ls_prev_ghosts : list ghost_state;  (** ghost_state positions last tick (for lerp). *)
  ls_last_tick : nat;           (** Timestamp of the last logic tick. *)
  ls_start_time : nat;          (** Timestamp when the game started. *)
  ls_texture : sdl_texture;     (** Player sprite texture. *)
  ls_phase : phase;             (** Current game phase. *)
  ls_phase_time : nat;          (** Timestamp when current phase started. *)
  ls_quit : bool                (** Whether the player has requested quit. *)
}.

(** * Process one frame (non-recursive) *)

(** Enforce frame timing: delay if the frame was faster than [frame_ms]. *)
Definition frame_delay (frame_start : nat) : IO void :=
  now2 <- sdl_get_ticks ;;
  let elapsed := now2 - frame_start in
  if Nat.ltb elapsed frame_ms
  then sdl_delay (frame_ms - elapsed)
  else Ret ghost.

(** The collision distance threshold in pixels. *)
Definition collision_threshold : nat := 22.

Definition snd_checkmark : PrimString.string := "assets/checkmark.mp3".
Definition snd_game_over : PrimString.string := "assets/game-over.mp3".
Definition snd_kill_ghost : PrimString.string := "assets/kill-ghost.mp3".
Definition snd_lose_life : PrimString.string := "assets/lose-life.mp3".
Definition snd_tap : PrimString.string := "assets/tap.mp3".
Definition snd_win : PrimString.string := "assets/win.mp3".

Definition play_cell_sound (c : cell) : IO void :=
  match c with
  | Dot => sdl_play_sound snd_tap
  | PowerPellet => sdl_play_sound snd_checkmark
  | _ => Ret ghost
  end.

(** Process a single frame: poll input, advance game logic,
    check pixel collisions, render, and enforce frame timing.
    Returns [(quit, new_loop_state)] for the C++ while loop. *)
Definition process_frame (ren : sdl_renderer) (ls : loop_state)
  : IO (bool * loop_state) :=
  ev <- sdl_poll_event ;;
  if Nat.eqb ev 1 then Ret (true, ls)
  else
  now <- sdl_get_ticks ;;
  let time_ms := now - ls_start_time ls in
  match ls_phase ls with
  | Playing =>
    let gs1 := apply_direction ev (ls_game ls) in
    let elapsed := now - ls_last_tick ls in
    let do_tick := Nat.leb tick_ms elapsed in
    let gs2 := if do_tick then tick gs1 else gs1 in
    let new_prev_pac := if do_tick then pacpos gs1
                        else ls_prev_pac ls in
    let new_prev_ghosts := if do_tick then ghosts gs1
                           else ls_prev_ghosts ls in
    let new_last_tick := if do_tick then now else ls_last_tick ls in
    let eaten_cell := if do_tick
                      then get_cell (prow (pacpos gs2)) (pcol (pacpos gs2))
                                    (board gs1)
                      else Empty in
    let t_num := now - new_last_tick in
    (* Compute interpolated player position *)
    let ppx := lerp (cell_center_x (pcol new_prev_pac))
                    (cell_center_x (pcol (pacpos gs2))) t_num tick_ms in
    let ppy := lerp (cell_center_y (prow new_prev_pac))
                    (cell_center_y (prow (pacpos gs2))) t_num tick_ms in
    (* Check for win *)
    if game_won gs2 then
      sdl_play_sound snd_win ;;
      render_frame ren (ls_texture ls) gs2 new_prev_pac new_prev_ghosts
                   t_num tick_ms time_ms ;;
      Ret (false, mkLoop gs2 new_prev_pac new_prev_ghosts
                         new_last_tick (ls_start_time ls) (ls_texture ls)
                         WinScreen now false)
    else
    (* Check pixel collision with ghosts *)
    match find_pixel_collision ppx ppy (ghosts gs2) new_prev_ghosts
            t_num tick_ms collision_threshold 0 with
    | Some (idx, Frightened) =>
      let gs3 := eat_ghost_idx idx gs2 in
      let next_ls := mkLoop gs3 new_prev_pac new_prev_ghosts
                            new_last_tick (ls_start_time ls) (ls_texture ls)
                            Playing 0 false in
      sdl_play_sound snd_kill_ghost ;;
      render_frame ren (ls_texture ls) gs3 (ls_prev_pac next_ls)
                   (ls_prev_ghosts next_ls)
                   t_num tick_ms time_ms ;;
      frame_delay now ;;
      Ret (false, next_ls)
    | Some (_, Chase) =>
      let gs3 := lose_one_life gs2 in
      let next_pac := pacpos gs3 in
      let next_ghosts := ghosts gs3 in
      if Nat.eqb (lives gs3) 0 then
        let next_ls := mkLoop gs3 next_pac next_ghosts
                              now (ls_start_time ls) (ls_texture ls)
                              GameOverScreen now false in
        sdl_play_sound snd_game_over ;;
        Ret (false, next_ls)
      else
        let next_ls := mkLoop gs3 next_pac next_ghosts
                              now (ls_start_time ls) (ls_texture ls)
                              DeathPause now false in
        sdl_play_sound snd_lose_life ;;
        Ret (false, next_ls)
    | None =>
      play_cell_sound eaten_cell ;;
      render_frame ren (ls_texture ls) gs2 new_prev_pac new_prev_ghosts
                   t_num tick_ms time_ms ;;
      frame_delay now ;;
      Ret (false, mkLoop gs2 new_prev_pac new_prev_ghosts
                         new_last_tick (ls_start_time ls) (ls_texture ls)
                         Playing 0 false)
    end

  | DeathPause =>
    if Nat.leb 2000 (now - ls_phase_time ls) then
      Ret (false, mkLoop (ls_game ls) (pacpos (ls_game ls))
                         (ghosts (ls_game ls)) now (ls_start_time ls)
                         (ls_texture ls) Playing 0 false)
    else
      draw_message_screen ren (msg_lives_left (lives (ls_game ls))) ;;
      frame_delay now ;;
      Ret (false, ls)

  | GameOverScreen =>
    if Nat.leb 3000 (now - ls_phase_time ls) then
      Ret (true, ls)
    else
      draw_message_screen ren msg_game_over ;;
      frame_delay now ;;
      Ret (false, ls)

  | WinScreen =>
    if Nat.leb 3000 (now - ls_phase_time ls) then
      Ret (true, ls)
    else
      draw_message_screen ren msg_you_win ;;
      frame_delay now ;;
      Ret (false, ls)
  end.

(** * Init and cleanup *)

(** Initialize SDL, create the window and renderer, and build the
    initial [loop_state]. Returns the window, renderer, and loop state. *)
Definition init_game : IO (sdl_window * sdl_renderer * loop_state) :=
  win <- sdl_create_window "Rocqman" win_width win_height ;;
  ren <- sdl_create_renderer win ;;
  tex <- sdl_load_texture ren "assets/rocq.svg" ;;
  t0 <- sdl_get_ticks ;;
  let gs := initial_state in
  let ls := mkLoop gs (pacpos gs) (ghosts gs) t0 t0 tex Playing 0 false in
  Ret (win, ren, ls).

(** Destroy the renderer and window, shutting down SDL. *)
Definition cleanup (ren : sdl_renderer) (win : sdl_window) : IO void :=
  sdl_destroy ren win.

End Rocqman.

Import Rocqman.
Import MonadNotations.

Axiom c_int : Type.
Axiom c_zero : c_int.

Definition exit_game (win : sdl_window) (ren : sdl_renderer) : IO c_int :=
  cleanup ren win ;;
  Ret c_zero.

Fixpoint run_game (fuel : nat) (win : sdl_window) (ren : sdl_renderer)
                  (ls : loop_state) : IO c_int :=
  match fuel with
  | 0 => exit_game win ren
  | S fuel' =>
    res <- process_frame ren ls ;;
    let '(quit, new_ls) := res in
    if quit then
      exit_game win ren
    else
      run_game fuel' win ren new_ls
  end.

Definition main : IO c_int :=
  init <- init_game ;;
  let '(win_ren, ls) := init in
  let '(win, ren) := win_ren in
  run_game 1000000 win ren ls.

Crane Extract Inlined Constant c_int => "int".
Crane Extract Inlined Constant c_zero => "0".

(** * Extraction

    Extract the [Rocqman] module to C++ files [rocqman.h] and [rocqman.cpp]. *)

Crane Extraction "rocqman" Rocqman main.
