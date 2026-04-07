From Stdlib Require Import Lia Bool PeanoNat.
From CraneSDL2 Require Import SDL.
From RocqmanGame Require Import Rocqman.

Import Rocqman.

(** * Pure game-state transitions used by [process_frame] *)

(** Relates a state to the pure gameplay updates that [process_frame] can apply. *)
Inductive pure_step : game_state -> game_state -> Prop :=
| PureStepApplyDirection : forall key gs,
    pure_step gs (apply_direction key gs)
| PureStepTick : forall gs,
    pure_step gs (tick gs)
| PureStepEatGhost : forall idx gs,
    pure_step gs (eat_ghost_idx idx gs)
| PureStepLoseOneLife : forall gs,
    pure_step gs (lose_one_life gs).

(** * Basic preservation lemmas *)

(** Changing direction never changes the current score. *)
Lemma apply_direction_score :
  forall key gs, score (apply_direction key gs) = score gs.
Proof.
  intros key gs.
  unfold apply_direction, set_direction.
  destruct key; simpl; try reflexivity;
    destruct (can_move _ _ _); reflexivity.
Qed.

(** Changing direction never changes the number of lives. *)
Lemma apply_direction_lives :
  forall key gs, lives (apply_direction key gs) = lives gs.
Proof.
  intros key gs.
  unfold apply_direction, set_direction.
  destruct key; simpl; try reflexivity;
    destruct (can_move _ _ _); reflexivity.
Qed.

(** Changing direction never changes the number of collectibles left. *)
Lemma apply_direction_dots_left :
  forall key gs, dots_left (apply_direction key gs) = dots_left gs.
Proof.
  intros key gs.
  unfold apply_direction, set_direction.
  destruct key; simpl; try reflexivity;
    destruct (can_move _ _ _); reflexivity.
Qed.

(** Moving ghosts leaves the score untouched. *)
Lemma move_ghosts_score :
  forall gs, score (move_ghosts gs) = score gs.
Proof.
  intros gs. reflexivity.
Qed.

(** Moving ghosts leaves the life count untouched. *)
Lemma move_ghosts_lives :
  forall gs, lives (move_ghosts gs) = lives gs.
Proof.
  intros gs. reflexivity.
Qed.

(** Moving ghosts leaves the collectible count untouched. *)
Lemma move_ghosts_dots_left :
  forall gs, dots_left (move_ghosts gs) = dots_left gs.
Proof.
  intros gs. reflexivity.
Qed.

(** Ticking the power timer does not award or remove score. *)
Lemma tick_power_score :
  forall gs, score (tick_power gs) = score gs.
Proof.
  intros gs.
  unfold tick_power.
  destruct (power_timer gs); reflexivity.
Qed.

(** Ticking the power timer does not change the number of lives. *)
Lemma tick_power_lives :
  forall gs, lives (tick_power gs) = lives gs.
Proof.
  intros gs.
  unfold tick_power.
  destruct (power_timer gs); reflexivity.
Qed.

(** Ticking the power timer does not change the number of collectibles. *)
Lemma tick_power_dots_left :
  forall gs, dots_left (tick_power gs) = dots_left gs.
Proof.
  intros gs.
  unfold tick_power.
  destruct (power_timer gs); reflexivity.
Qed.

(** Eating a frightened ghost only increases score, by a fixed bonus. *)
Lemma eat_ghost_idx_score_monotone :
  forall idx gs, score gs <= score (eat_ghost_idx idx gs).
Proof.
  intros idx gs.
  unfold eat_ghost_idx.
  simpl.
  lia.
Qed.

(** Eating a frightened ghost never changes the life count. *)
Lemma eat_ghost_idx_lives :
  forall idx gs, lives (eat_ghost_idx idx gs) = lives gs.
Proof.
  intros idx gs.
  unfold eat_ghost_idx.
  reflexivity.
Qed.

(** Eating a frightened ghost never changes the remaining collectibles. *)
Lemma eat_ghost_idx_dots_left :
  forall idx gs, dots_left (eat_ghost_idx idx gs) = dots_left gs.
Proof.
  intros idx gs.
  unfold eat_ghost_idx.
  reflexivity.
Qed.

(** Losing a life never changes the accumulated score. *)
Lemma lose_one_life_score :
  forall gs, score (lose_one_life gs) = score gs.
Proof.
  intros gs.
  unfold lose_one_life.
  reflexivity.
Qed.

(** Losing a life can only decrease the life count by at most one. *)
Lemma lose_one_life_lives_monotone :
  forall gs, lives (lose_one_life gs) <= lives gs.
Proof.
  intros gs.
  unfold lose_one_life.
  destruct (lives gs); simpl; lia.
Qed.

(** Losing a life never changes the remaining collectibles. *)
Lemma lose_one_life_dots_left :
  forall gs, dots_left (lose_one_life gs) = dots_left gs.
Proof.
  intros gs.
  unfold lose_one_life.
  reflexivity.
Qed.

(** * Monotonicity of the main logical tick *)

(** One player-movement step can only keep or increase the score. *)
Lemma move_pacman_score_monotone :
  forall gs, score gs <= score (move_pacman gs).
Proof.
  intros gs.
  unfold move_pacman.
  destruct (game_over gs || game_won gs); simpl; [lia|].
  destruct (can_move (desired_dir gs) (pacpos gs) (board gs)); simpl;
    (match goal with |- context [is_wall ?a ?b ?c] =>
       destruct (is_wall a b c); simpl; [lia|] end);
    (match goal with |- context [get_cell ?a ?b ?c] =>
       destruct (get_cell a b c); simpl; lia end).
Qed.

(** One player-movement step never changes the life count directly. *)
Lemma move_pacman_lives :
  forall gs, lives (move_pacman gs) = lives gs.
Proof.
  intros gs.
  unfold move_pacman.
  destruct (game_over gs || game_won gs); simpl; [reflexivity|].
  destruct (can_move (desired_dir gs) (pacpos gs) (board gs)); simpl;
    match goal with |- context [is_wall ?a ?b ?c] =>
      destruct (is_wall a b c); simpl; reflexivity end.
Qed.

(** One player-movement step can only keep or decrease the collectible count. *)
Lemma move_pacman_dots_left_monotone :
  forall gs, dots_left (move_pacman gs) <= dots_left gs.
Proof.
  intros gs.
  unfold move_pacman.
  destruct (game_over gs || game_won gs); simpl; [lia|].
  destruct (can_move (desired_dir gs) (pacpos gs) (board gs)); simpl;
    (match goal with |- context [is_wall ?a ?b ?c] =>
       destruct (is_wall a b c); simpl; [lia|] end);
    (match goal with |- context [get_cell ?a ?b ?c] =>
       destruct (get_cell a b c); simpl;
       destruct (dots_left gs); simpl; lia end).
Qed.

(** A full logical tick can only keep or increase the score. *)
Theorem tick_score_monotone :
  forall gs, score gs <= score (tick gs).
Proof.
  intros gs.
  unfold tick.
  destruct (game_over gs || game_won gs) eqn:Hterminal; simpl; try lia.
  rewrite tick_power_score.
  rewrite move_ghosts_score.
  apply move_pacman_score_monotone.
Qed.

(** A full logical tick can only keep or decrease the life count. *)
Theorem tick_lives_nonincreasing :
  forall gs, lives (tick gs) <= lives gs.
Proof.
  intros gs.
  unfold tick.
  destruct (game_over gs || game_won gs) eqn:Hterminal; simpl; try lia.
  rewrite tick_power_lives.
  rewrite move_ghosts_lives.
  rewrite move_pacman_lives.
  lia.
Qed.

(** A full logical tick can only keep or decrease the collectible count. *)
Theorem tick_dots_left_nonincreasing :
  forall gs, dots_left (tick gs) <= dots_left gs.
Proof.
  intros gs.
  unfold tick.
  destruct (game_over gs || game_won gs) eqn:Hterminal; simpl; try lia.
  rewrite tick_power_dots_left.
  rewrite move_ghosts_dots_left.
  apply move_pacman_dots_left_monotone.
Qed.

(** Terminal logical states are fixed points of the tick function. *)
Theorem tick_terminal_noop :
  forall gs,
    game_over gs = true \/ game_won gs = true ->
    tick gs = gs.
Proof.
  intros gs Hterminal.
  unfold tick.
  destruct (game_over gs || game_won gs) eqn:Horb; try reflexivity.
  apply Bool.orb_false_iff in Horb.
  destruct Horb as [Hover Hwon].
  destruct Hterminal; congruence.
Qed.

(** * The requested monotonicity properties over pure gameplay steps *)

(** Every pure gameplay step preserves score monotonicity. *)
Theorem pure_step_score_monotone :
  forall gs gs',
    pure_step gs gs' ->
    score gs <= score gs'.
Proof.
  intros gs gs' Hstep.
  inversion Hstep; subst; clear Hstep.
  - rewrite apply_direction_score. lia.
  - apply tick_score_monotone.
  - apply eat_ghost_idx_score_monotone.
  - rewrite lose_one_life_score. lia.
Qed.

(** Every pure gameplay step preserves nonincreasing lives. *)
Theorem pure_step_lives_nonincreasing :
  forall gs gs',
    pure_step gs gs' ->
    lives gs' <= lives gs.
Proof.
  intros gs gs' Hstep.
  inversion Hstep; subst; clear Hstep.
  - rewrite apply_direction_lives. lia.
  - apply tick_lives_nonincreasing.
  - rewrite eat_ghost_idx_lives. lia.
  - apply lose_one_life_lives_monotone.
Qed.

(** Every pure gameplay step preserves nonincreasing collectibles. *)
Theorem pure_step_dots_left_nonincreasing :
  forall gs gs',
    pure_step gs gs' ->
    dots_left gs' <= dots_left gs.
Proof.
  intros gs gs' Hstep.
  inversion Hstep; subst; clear Hstep.
  - rewrite apply_direction_dots_left. lia.
  - apply tick_dots_left_nonincreasing.
  - rewrite eat_ghost_idx_dots_left. lia.
  - rewrite lose_one_life_dots_left. lia.
Qed.

(** * Pure branch models for the paused and terminal-screen cases of [process_frame] *)

(** Models the pure state update performed by the paused branch of [process_frame]. *)
Definition paused_branch_result (ev : sdl_event) (now : nat) (ls : loop_state)
  : bool * loop_state :=
  match ev with
  | EventKeyDown KeySpace =>
    let gs := ls_game ls in
    (false, mkLoop gs (pacpos gs) (ghosts gs)
                   now (ls_start_time ls) (ls_texture ls)
                   Playing 0 false)
  | _ =>
    (false, ls)
  end.

(** Decides whether a terminal screen should quit once enough time has elapsed. *)
Definition terminal_screen_should_quit (now : nat) (ls : loop_state) : bool :=
  match ls_phase ls with
  | GameOverScreen => Nat.leb 3000 (now - ls_phase_time ls)
  | WinScreen => Nat.leb 3000 (now - ls_phase_time ls)
  | _ => false
  end.

(** A paused state remains paused as long as space is not pressed. *)
Theorem paused_branch_without_space_stays_paused :
  forall ls ev now,
    ls_phase ls = Paused ->
    ev <> EventKeyDown KeySpace ->
    ls_phase (snd (paused_branch_result ev now ls)) = Paused.
Proof.
  intros ls ev now Hphase Hspace.
  unfold paused_branch_result.
  destruct ev; simpl; try exact Hphase.
  destruct s; simpl; try exact Hphase.
  exfalso. apply Hspace. reflexivity.
Qed.

(** Pressing space in a paused state returns the phase to [Playing]. *)
Theorem paused_branch_with_space_returns_to_playing :
  forall ls now,
    ls_phase ls = Paused ->
    ls_phase (snd (paused_branch_result (EventKeyDown KeySpace) now ls)) = Playing.
Proof.
  intros ls now _.
  unfold paused_branch_result.
  simpl.
  reflexivity.
Qed.

(** Terminal screens eventually request quit once time has advanced past the timeout. *)
Theorem terminal_screen_eventually_quits :
  forall ls,
    ls_phase ls = WinScreen \/ ls_phase ls = GameOverScreen ->
    exists deadline,
      forall now,
        deadline <= now ->
        terminal_screen_should_quit now ls = true.
Proof.
  intros ls Hphase.
  exists (ls_phase_time ls + 3000).
  intros now Hnow.
  unfold terminal_screen_should_quit.
  destruct Hphase as [Hwin | Hover]; rewrite Hwin || rewrite Hover.
  all: apply Nat.leb_le; lia.
Qed.
