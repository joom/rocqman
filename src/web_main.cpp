#include <rocqman.h>

#include <emscripten.h>

#include <optional>
#include <utility>

namespace {

struct WebGame {
  sdl_window win = nullptr;
  sdl_renderer ren = nullptr;
  std::optional<Rocqman::loop_state> loop;
  bool cleaned_up = false;
};

void web_frame(void *arg) {
  auto *game = static_cast<WebGame *>(arg);
  if (game->cleaned_up) return;

  auto result = Rocqman::process_frame(game->ren, std::move(*game->loop));
  game->loop = std::move(result.second);

  if (result.first) {
    Rocqman::cleanup(game->ren, game->win);
    game->cleaned_up = true;
    emscripten_cancel_main_loop();
  }
}

} // namespace

int main() {
  static WebGame game;

  auto init = Rocqman::init_game();
  game.win = init.first.first;
  game.ren = init.first.second;
  game.loop.emplace(std::move(init.second));

  emscripten_set_main_loop_arg(web_frame, &game, 0, true);
  return 0;
}
