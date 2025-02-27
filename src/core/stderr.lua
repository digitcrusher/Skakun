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

local stderr = {}

function stderr.log(level, where, ...)
  io.stderr:write(level, ' ', tostring(where), ': ')
  local args = table.pack(...)
  for i = 1, args.n do
    io.stderr:write(tostring(args[i]))
  end
  io.stderr:write('\n')
end

function stderr.error(where, ...) stderr.log('error', where, ...) end
function stderr.warn(where, ...) stderr.log('warn', where, ...) end
function stderr.info(where, ...) stderr.log('info', where, ...) end

return stderr
