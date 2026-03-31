#pragma once
#include <SDL.h>
#include <SDL_image.h>
#include <cstdint>
#include <cstring>
#include <spawn.h>
#include <string>

extern char **environ;

// Opaque types for Rocq extraction
using sdl_window = SDL_Window*;
using sdl_renderer = SDL_Renderer*;
using sdl_texture = SDL_Texture*;

// SDL init / teardown
inline sdl_window sdl_create_window(const std::string &title,
                                    unsigned int w, unsigned int h) {
  if (SDL_Init(SDL_INIT_VIDEO) != 0) return nullptr;
  return SDL_CreateWindow(title.c_str(), SDL_WINDOWPOS_CENTERED,
                          SDL_WINDOWPOS_CENTERED, (int)w, (int)h,
                          SDL_WINDOW_SHOWN);
}

inline sdl_renderer sdl_create_renderer(sdl_window win) {
  return SDL_CreateRenderer(
      win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
}

inline void sdl_destroy(sdl_renderer ren, sdl_window win) {
  SDL_DestroyRenderer(ren);
  SDL_DestroyWindow(win);
  SDL_Quit();
}

// drawing primitives
inline void sdl_set_draw_color(sdl_renderer r,
                               unsigned int red, unsigned int green,
                               unsigned int blue) {
  SDL_SetRenderDrawColor(r, (uint8_t)red, (uint8_t)green, (uint8_t)blue, 255);
}

inline void sdl_clear(sdl_renderer r) {
  SDL_RenderClear(r);
}

inline void sdl_present(sdl_renderer r) {
  SDL_RenderPresent(r);
}

inline void sdl_fill_rect(sdl_renderer r,
                          unsigned int x, unsigned int y,
                          unsigned int w, unsigned int h) {
  SDL_Rect rect = {(int)x, (int)y, (int)w, (int)h};
  SDL_RenderFillRect(r, &rect);
}

inline void sdl_draw_point(sdl_renderer r,
                           unsigned int x, unsigned int y) {
  SDL_RenderDrawPoint(r, (int)x, (int)y);
}

// event polling
// Returns: 0=none, 1=quit, 2=up, 3=down, 4=left, 5=right
inline unsigned int sdl_poll_event() {
  SDL_Event ev;
  unsigned int result = 0;
  while (SDL_PollEvent(&ev)) {
    if (ev.type == SDL_QUIT) return 1;
    if (ev.type == SDL_KEYDOWN) {
      switch (ev.key.keysym.sym) {
      case SDLK_ESCAPE:
      case SDLK_q:
        return 1;
      case SDLK_UP:
      case SDLK_w:
        result = 2;
        break;
      case SDLK_DOWN:
      case SDLK_s:
        result = 3;
        break;
      case SDLK_LEFT:
      case SDLK_a:
        result = 4;
        break;
      case SDLK_RIGHT:
      case SDLK_d:
        result = 5;
        break;
      default:
        break;
      }
    }
  }
  return result;
}

// timing
inline unsigned int sdl_get_ticks() {
  return (unsigned int)SDL_GetTicks();
}

inline void sdl_delay(unsigned int ms) {
  SDL_Delay(ms);
}

// textures
inline sdl_texture sdl_load_texture(sdl_renderer ren,
                                    const std::string &path) {
  SDL_Surface *surface = IMG_Load(path.c_str());
  if (!surface) return nullptr;
  SDL_Texture *tex = SDL_CreateTextureFromSurface(ren, surface);
  SDL_FreeSurface(surface);
  return tex;
}

inline void sdl_play_sound(const std::string &path) {
  if (path.empty()) return;
  auto try_spawn = [&](const char *prog, char *const argv[]) -> bool {
    pid_t pid;
    return posix_spawnp(&pid, prog, nullptr, nullptr, argv, environ) == 0;
  };

#if defined(__APPLE__)
  char *const afplay_argv[] = {
      const_cast<char *>("afplay"),
      const_cast<char *>(path.c_str()),
      nullptr
  };
  (void)try_spawn("afplay", afplay_argv);
#elif defined(__linux__)
  char *const mpg123_argv[] = {
      const_cast<char *>("mpg123"),
      const_cast<char *>("-q"),
      const_cast<char *>(path.c_str()),
      nullptr
  };
  if (try_spawn("mpg123", mpg123_argv)) return;

  char *const ffplay_argv[] = {
      const_cast<char *>("ffplay"),
      const_cast<char *>("-nodisp"),
      const_cast<char *>("-autoexit"),
      const_cast<char *>("-loglevel"),
      const_cast<char *>("quiet"),
      const_cast<char *>(path.c_str()),
      nullptr
  };
  if (try_spawn("ffplay", ffplay_argv)) return;

  char *const play_argv[] = {
      const_cast<char *>("play"),
      const_cast<char *>("-q"),
      const_cast<char *>(path.c_str()),
      nullptr
  };
  (void)try_spawn("play", play_argv);
#else
  (void)path;
#endif
}

inline void sdl_render_texture_rotated(sdl_renderer ren, sdl_texture tex,
                                       unsigned int cx, unsigned int cy,
                                       unsigned int w, unsigned int h,
                                       unsigned int angle_deg,
                                       bool flip_h) {
  SDL_Rect dst = {(int)(cx - w / 2), (int)(cy - h / 2), (int)w, (int)h};
  SDL_RendererFlip flip = flip_h ? SDL_FLIP_HORIZONTAL : SDL_FLIP_NONE;
  SDL_RenderCopyEx(ren, tex, nullptr, &dst,
                   (double)angle_deg, nullptr, flip);
}
