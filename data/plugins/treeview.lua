local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"

config.treeview_size = 200 * SCALE

local function get_depth(filename)
  local n = 0
  for sep in filename:gmatch("[\\/]") do
    n = n + 1
  end
  return n
end


local TreeView = View:extend()

function TreeView:new()
  TreeView.super.new(self)
  self.scrollable = true
  self.visible = true
  self.init_size = true
  self.cache = {}
  self.expand_version = 0
end


function TreeView:get_cached(item)
  local t = self.cache[item.filename]
  if not t then
    t = {}
    t.filename = item.filename
    t.abs_filename = system.absolute_path(item.filename)
    t.name = t.filename:match("[^\\/]+$")
    t.depth = get_depth(t.filename)
    t.type = item.type
    self.cache[t.filename] = t
  end
  return t
end


function TreeView:get_name()
  return "Project"
end


function TreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end


function TreeView:get_scrollable_size()
  local count = 0
  for _ in self:each_item() do count = count + 1 end
  return count * self:get_item_height() + style.padding.y
end


-- widest row in pixels; cached, recomputed only when the file list changes.
-- mirrors the x-advance in draw() exactly so scroll reaches the longest name.
function TreeView:get_content_width()
  if self.content_width and self.content_width_key == self.expand_version then
    return self.content_width
  end
  local icon_width = style.icon_font:get_width("D")
  local spacing = style.font:get_width(" ") * 2
  local max = 0
  for item in self:each_item() do
    -- indent + icon area (same for dir and file) + spacing + name
    local w = item.depth * style.padding.x + style.padding.x
      + style.padding.x + icon_width
      + spacing + style.font:get_width(item.name)
    if w > max then max = w end
  end
  self.content_width = max + style.padding.x
  self.content_width_key = self.expand_version
  return self.content_width
end


function TreeView:check_cache()
  -- invalidate cache's skip values if project_files has changed
  if core.project_files ~= self.last_project_files then
    for _, v in pairs(self.cache) do
      v.skip = nil
    end
    self.last_project_files = core.project_files
    self.expand_version = (self.expand_version or 0) + 1
  end
end


function TreeView:each_item()
  return coroutine.wrap(function()
    self:check_cache()
    local ox, oy = self:get_content_offset()
    local y = oy + style.padding.y
    local w = self.size.x
    local h = self:get_item_height()

    local i = 1
    while i <= #core.project_files do
      local item = core.project_files[i]
      local cached = self:get_cached(item)

      coroutine.yield(cached, ox, y, w, h)
      y = y + h
      i = i + 1

      if not cached.expanded then
        if cached.skip then
          i = cached.skip
        else
          local depth = cached.depth
          while i <= #core.project_files do
            local filename = core.project_files[i].filename
            if get_depth(filename) <= depth then break end
            i = i + 1
          end
          cached.skip = i
        end
      end
    end
  end)
end


function TreeView:on_mouse_moved(px, py, dx, dy)
  TreeView.super.on_mouse_moved(self, px, py, dx, dy)
  if self.dragging_hscrollbar then
    self.scroll.to.x = self.scroll.to.x + self:get_content_width() / self.size.x * dx
  end
  if self.dragging_scrollbar or self.dragging_hscrollbar then return end
  self.hovered_item = nil
  for item, x,y,w,h in self:each_item() do
    if px > x and py > y and px <= x + w and py <= y + h then
      self.hovered_item = item
      break
    end
  end
end


function TreeView:on_mouse_pressed(button, x, y, clicks)
  local caught = TreeView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then
    return
  end
  if self:hscrollbar_overlaps_point(x, y) then
    self.dragging_hscrollbar = true
    return
  end
  if not self.hovered_item then
    return
  elseif self.hovered_item.type == "dir" then
    self.hovered_item.expanded = not self.hovered_item.expanded
    self.expand_version = self.expand_version + 1
  else
    core.try(function()
      core.root_view:open_doc(core.open_doc(self.hovered_item.filename))
    end)
  end
end


function TreeView:on_mouse_released(button, x, y)
  TreeView.super.on_mouse_released(self, button, x, y)
  self.dragging_hscrollbar = false
end


function TreeView:on_mouse_wheel(y, x)
  if x and x ~= 0 then
    self.scroll.to.x = self.scroll.to.x + x * -config.mouse_wheel_scroll
  elseif keymap.modkeys["shift"] then
    self.scroll.to.x = self.scroll.to.x + y * -config.mouse_wheel_scroll
  else
    TreeView.super.on_mouse_wheel(self, y)
  end
end


-- horizontal scrollbar at the bottom of the panel
function TreeView:get_hscrollbar_rect()
  local cw = self:get_content_width()
  if cw <= self.size.x then return 0, 0, 0, 0 end
  local w = math.max(20, self.size.x * self.size.x / cw)
  return
    self.position.x + self.scroll.x * (self.size.x - w) / (cw - self.size.x),
    self.position.y + self.size.y - style.scrollbar_size,
    w,
    style.scrollbar_size
end


function TreeView:hscrollbar_overlaps_point(x, y)
  local sx, sy, sw, sh = self:get_hscrollbar_rect()
  return sw > 0 and x >= sx and x < sx + sw and y >= sy - sh * 3 and y < sy + sh
end


function TreeView:update()
  -- update width
  local dest = self.visible and config.treeview_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = false
  else
    self:move_towards(self.size, "x", dest)
  end

  -- clamp horizontal scroll before super lerps it (base View only clamps y)
  local maxx = math.max(0, self:get_content_width() - self.size.x)
  self.scroll.to.x = common.clamp(self.scroll.to.x, 0, maxx)
  self.scroll.x = common.clamp(self.scroll.x, 0, maxx)

  TreeView.super.update(self)
end


function TreeView:draw()
  self:draw_background(style.background2)

  local icon_width = style.icon_font:get_width("D")
  local spacing = style.font:get_width(" ") * 2

  local doc = core.active_view.doc
  local active_filename = doc and system.absolute_path(doc.filename or "")

  core.push_clip_rect(self.position.x, self.position.y, self.size.x, self.size.y)
  for item, x,y,w,h in self:each_item() do
    local color = style.text

    -- highlight active_view doc
    if item.abs_filename == active_filename then
      color = style.accent
    end

    -- hovered item background
    if item == self.hovered_item then
      renderer.draw_rect(x, y, w, h, style.line_highlight)
      color = style.accent
    end

    -- icons
    x = x + item.depth * style.padding.x + style.padding.x
    if item.type == "dir" then
      local icon1 = item.expanded and "-" or "+"
      local icon2 = item.expanded and "D" or "d"
      common.draw_text(style.icon_font, color, icon1, nil, x, y, 0, h)
      x = x + style.padding.x
      common.draw_text(style.icon_font, color, icon2, nil, x, y, 0, h)
      x = x + icon_width
    else
      x = x + style.padding.x
      common.draw_text(style.icon_font, color, "f", nil, x, y, 0, h)
      x = x + icon_width
    end

    -- text
    x = x + spacing
    x = common.draw_text(style.font, color, item.name, nil, x, y, 0, h)
  end
  core.pop_clip_rect()

  self:draw_scrollbar()

  -- horizontal scrollbar
  local hx, hy, hw, hh = self:get_hscrollbar_rect()
  if hw > 0 then
    local color = self.dragging_hscrollbar and style.scrollbar2 or style.scrollbar
    renderer.draw_rect(hx, hy, hw, hh, color)
  end
end


-- init
local view = TreeView()
local node = core.root_view:get_active_node()
node:split("left", view, true)

-- register commands and keymap
command.add(nil, {
  ["treeview:toggle"] = function()
    view.visible = not view.visible
  end,
})

keymap.add { ["ctrl+\\"] = "treeview:toggle" }
