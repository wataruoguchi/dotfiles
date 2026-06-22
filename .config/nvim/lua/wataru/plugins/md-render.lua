return {
  "delphinus/md-render.nvim",
  ft = { "markdown" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("md-render").setup()
  end,
}
