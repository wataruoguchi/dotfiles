return {
  "3rd/diagram.nvim",
  ft = { "markdown", "norg" },
  dependencies = {
    {
      "3rd/image.nvim",
      build = false,
      opts = {
        -- WezTerm speaks the Kitty graphics protocol (officially "unsupported"
        -- by image.nvim, but works for diagram rendering). Switch to Kitty if
        -- rendering misbehaves.
        backend = "kitty",
        -- Use the ImageMagick CLI (`magick`) instead of the luarock, so no
        -- luarocks/hererocks toolchain is required.
        processor = "magick_cli",
      },
    },
  },
  opts = {
    events = {
      render_buffer = { "InsertLeave", "BufWinEnter", "TextChanged" },
      clear_buffer = { "BufLeave" },
    },
    renderer_options = {
      mermaid = {
        theme = nil,
        scale = 1,
      },
      plantuml = {},
      d2 = {},
      gnuplot = {},
    },
  },
}
