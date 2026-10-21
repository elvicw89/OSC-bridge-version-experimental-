-- REAPER Remote: export waveform peaks of every audio item in the project
-- to reaper_www_root/waveforms.json so the remote page can draw them.
-- Run it from the Action list (Actions > Show action list > New action > Load ReaScript).
local RATE = 100   -- peak buckets per second
local SR   = 8000  -- analysis sample rate
local spb  = math.floor(SR / RATE)
local path = reaper.GetResourcePath() .. "/reaper_www_root/waveforms.json"

local function q(v, scale) -- clamp to -1..1 and store as an integer -127..127
  if v > 1 then v = 1 elseif v < -1 then v = -1 end
  return math.floor(v * 127 + 0.5)
end

local rp = reaper.GetResourcePath()
reaper.RecursiveCreateDirectory(rp .. "/reaper_www_root/icons", 0)

-- copy a track's icon into reaper_www_root/icons and return its relative url
local function exportIcon(tr, n)
  local _, p = reaper.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
  if not p or p == "" then return nil end
  local f = io.open(p, "rb") or io.open(rp .. "/Data/track_icons/" .. p, "rb")
  if not f then return nil end
  local data = f:read("a"); f:close()
  local rel = "icons/track_" .. n .. (p:match("(%.%w+)$") or ".png")
  local o = io.open(rp .. "/reaper_www_root/" .. rel, "wb")
  if not o then return nil end
  o:write(data); o:close()
  return rel
end

local tracks = {}
for ti = 0, reaper.CountTracks(0) - 1 do
  local tr, items = reaper.GetTrack(0, ti), {}
  for ii = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local item = reaper.GetTrackMediaItem(tr, ii)
    local take = reaper.GetActiveTake(item)
    if take and not reaper.TakeIsMIDI(take) then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local aa  = reaper.CreateTakeAudioAccessor(take)
      local nb, mn, mx = math.ceil(len * RATE), {}, {}
      local buf = reaper.new_array(RATE * spb)
      local b = 0
      while b < nb do
        local nbk = math.min(RATE, nb - b)
        local ns = nbk * spb
        local ok = reaper.GetAudioAccessorSamples(aa, SR, 1, b / RATE, ns, buf)
        local t = buf.table()
        for k = 0, nbk - 1 do
          local lo, hi = 0, 0
          if ok == 1 then
            for s = 1, spb do
              local v = t[k * spb + s]
              if v < lo then lo = v elseif v > hi then hi = v end
            end
          end
          mn[#mn + 1], mx[#mx + 1] = q(lo), q(hi)
        end
        b = b + nbk
      end
      reaper.DestroyAudioAccessor(aa)
      items[#items + 1] = string.format('{"pos":%.4f,"len":%.4f,"mn":[%s],"mx":[%s]}',
        pos, len, table.concat(mn, ","), table.concat(mx, ","))
    end
  end
  local c, col = reaper.GetTrackColor(tr), "null"
  if c ~= 0 then
    local r, g, b = reaper.ColorFromNative(c & 0xFFFFFF)
    col = string.format('"#%02x%02x%02x"', r, g, b)
  end
  local ic = exportIcon(tr, ti + 1)
  tracks[#tracks + 1] = string.format('{"idx":%d,"color":%s,"icon":%s,"items":[%s]}',
    ti + 1, col, ic and ('"' .. ic .. '"') or "null", table.concat(items, ","))
end

local f = io.open(path, "w")
if not f then
  reaper.ShowMessageBox("Can't write " .. path .. "\nCreate the reaper_www_root folder in REAPER's resource path first.", "Export waveforms", 0)
  return
end
f:write('{"rate":' .. RATE .. ',"tracks":[' .. table.concat(tracks, ",") .. ']}')
f:close()
reaper.ShowMessageBox("Waveforms exported. Click 'Reload waveforms' on the remote page.", "Export waveforms", 0)
