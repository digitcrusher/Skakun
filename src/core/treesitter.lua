-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local here = ...
local lanes   =       require('lanes')
local cjson   = lanes.require('cjson')
local core    = lanes.require('core')
local stderr  = lanes.require('core.stderr')
local utils   = lanes.require('core.utils')
local binding = lanes.require('lanes.lua_tree_sitter')

local treesitter = setmetatable({
  pkgs = {},

  linda = lanes.linda(here),
  _grammars = {},
  pkg_loader = nil,
}, { __index = binding })

-- for _, lang in ipairs({'agda', 'bash', 'c', 'cpp', 'c-sharp', 'css', 'embedded-template', 'go', 'haskell', 'html', 'java', 'javascript', 'jsdoc', 'json', 'julia', 'ocaml', 'php', 'python', 'ql', 'ql-dbscheme', 'regex', 'ruby', 'rust', 'scala', 'typescript', 'verilog'}) do
--   table.insert(treesitter.pkgs, 'https://github.com/tree-sitter/tree-sitter-' .. lang)
-- end
-- for _, lang in ipairs({'arduino', 'bicep', 'bitbake', 'cairo', 'capnp', 'chatito', 'commonlisp', 'cpon', 'csv', 'cuda', 'doxygen', 'firrtl', 'func', 'gitattributes', 'glsl', 'gn', 'go-sum', 'gpg-config', 'gstlaunch', 'hare', 'hcl', 'hlsl', 'hyprlang', 'ispc', 'kconfig', 'kdl', 'kotlin', 'linkerscript', 'lua', 'luadoc', 'luap', 'luau', 'make', 'markdown', 'meson', 'move', 'nqc', 'objc', 'odin', 'pem', 'po', 'poe-filter', 'pony', 'printf', 'properties', 'puppet', 'pymanifest', 'qmldir', 'query', 're2c', 'readline', 'requirements', 'ron', 'scss', 'slang', 'smali', 'squirrel', 'ssh-config', 'starlark', 'svelte', 'tablegen', 'tcl', 'test', 'thrift', 'toml', 'udev', 'ungrammar', 'uxntal', 'vim', 'vue', 'wgsl-bevy', 'xcompose', 'xml', 'yaml', 'yuck', 'zig', 'zsh'}) do
--   table.insert(treesitter.pkgs, 'https://github.com/tree-sitter-grammars/tree-sitter-' .. lang)
-- end
table.insert(treesitter.pkgs, 'https://github.com/tree-sitter-grammars/tree-sitter-lua')

function treesitter.grammars()
  while true do
    local _, grammar = treesitter.linda:receive(0, 'grammar')
    if not grammar then break end
    table.insert(treesitter._grammars, grammar)
  end
  return treesitter._grammars
end

function treesitter.start_pkg_loader()
  treesitter.pkg_loader = utils.start_lane({'cjson', 'core.utils', 'lanes.lua_tree_sitter'}, treesitter.load_pkgs)
end

function treesitter.stop_pkg_loader()
  if treesitter.pkg_loader then
    treesitter.pkg_loader:cancel('soft')
    treesitter.pkg_loader = nil
  end
end

function treesitter.load_pkgs()
  local start = utils.timer()
  local leftovers = {}
  for _, url in ipairs(treesitter.pkgs) do
    if cancel_test() then return end
    xpcall(
      treesitter.load_pkg,
      function(err)
        table.insert(leftovers, url)
        stderr.warn(here, err)
      end,
      core.cache_dir .. '/' .. here .. '/' .. utils.slugify(url)
    )
  end
  stderr.info(here, ('pkg preload done in %.2fs'):format(utils.timer() - start))

  for _, url in ipairs(leftovers) do
    if cancel_test() then return end
    xpcall(
      function()
        local dir = treesitter.download_pkg(url)
        treesitter.build_pkg(dir)
        treesitter.load_pkg(dir)
      end,
      function(err)
        if err then
          stderr.error(here, err)
        end
      end
    )
  end
  stderr.info(here, ('pkg load done in %.2fs'):format(utils.timer() - start))
end

function treesitter.download_pkg(url)
  stderr.info(here, 'downloading pkg ', url)

  local slug = utils.slugify(url)
  local dest = core.cache_dir .. '/' .. here .. '/' .. slug

  if not os.rename(dest, dest) then
    if os.execute(('git ls-remote %q > /dev/null 2>&1'):format(url)) then
      assert(os.execute(('git clone --depth=1 -q %q %q'):format(url, dest)))
    else
      local temp = core.cache_dir .. '/' .. here .. '/.' .. slug
      local pipe = io.popen('{ ' .. table.concat({
        ('mkdir -p %q/%q'):format(core.cache_dir, here),
        ('wget %q -O %q'):format(url, temp),
        ('tar -xf %q --one-top-level=%q'):format(temp, dest),
        ('rm %q'):format(temp),
      }, ' && ') .. '; } 2>&1', 'r')
      local log = pipe:read('a')
      if not pipe:close() then
        stderr.error(here, log)
        error()
      end
    end

  elseif os.execute(('git -C %q rev-parse 2> /dev/null'):format(dest)) then
    local pipe = io.popen(('git -C %q pull --depth=1 2>&1'):format(dest), 'r')
    local log = pipe:read('a')
    if not pipe:close() then
      error(log)
    elseif not log:match('^Already up to date.\n') then
      stderr.info(here, log)
      assert(os.execute(('git -C %q clean -dfX'):format(dest)))
    end
  end

  return dest
end

function treesitter.build_pkg(dir)
  stderr.info(here, 'building pkg ', dir)

  local pipe = io.popen(('find %q -name tree-sitter.json -printf %%h\\\\0'):format(dir), 'r')
  local roots = pipe:read('a')
  assert(pipe:close())
  if roots == '' then
    stderr.warn(here, 'no tree-sitter.json in ', dir)
  end

  for root in utils.split(roots, '\0') do
    local pipe = io.popen(('make -C %q CFLAGS=-O3\\ -march=native -j 2>&1'):format(root), 'r')
    local log = pipe:read('a')
    if not pipe:close() then
      stderr.error(here, log)
      error()
    end
  end
end

function treesitter.load_pkg(dir)
  stderr.info(here, 'loading pkg ', dir)

  local pipe = io.popen(('find %q -name tree-sitter.json -printf %%h\\\\0'):format(dir), 'r')
  local roots = pipe:read('a')
  assert(pipe:close())
  if #roots == 0 then
    stderr.warn(here, 'no tree-sitter.json in ', dir)
  end

  for root in utils.split(roots, '\0') do
    local file = io.open(root .. '/tree-sitter.json', 'r')
    local json = cjson.decode(file:read('a'))
    file:close()
    if #json.grammars == 0 then
      stderr.warn(here, 'no grammars in ', root)
    end

    for _, json in ipairs(json.grammars) do
      stderr.info(here, 'loading grammar ', json.scope, '/', json.name)

      local ok, lang = pcall(
        treesitter.Language.load,
        root .. '/' .. (json.path or '.') .. '/libtree-sitter-' .. json.name .. (core.platform == 'macos' and '.dylib' or '.so'),
        json.name:gsub('-', '_')
      )
      if not ok then
        lang = treesitter.Language.load(
          root .. '/' .. (json.path or '.') .. '/libtree-sitter-' .. json.name:gsub('_', '-') .. (core.platform == 'macos' and '.dylib' or '.so'),
          json.name:gsub('-', '_')
        )
      end

      local function load_queries(paths)
        if type(paths) ~= 'table' then
          paths = {paths}
        end
        local result = {}
        for _, path in ipairs(paths) do
          local file, err = io.open(root .. '/' .. path, 'r')
          if file then
            table.insert(result, file:read('a'))
            file:close()
          else
            stderr.warn(here, err)
          end
        end
        return treesitter.Query.new(lang, table.concat(result)) -- Treesitter is the bottleneck here.
      end

      treesitter.linda:send('grammar', {
        file_suffixes = json['file-types'] == cjson.null and {} or json['file-types'],
        injection_regex = json['injection-regex'],
        lang = lang,
        highlights = load_queries(json.highlights or 'queries/highlights.scm'),
        injections = load_queries(json.injections or 'queries/injections.scm'),
      })
    end
  end
end

return treesitter
