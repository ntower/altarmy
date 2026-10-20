-- AltArmy TBC — Pure helpers for graph hover/highlight logic.

if not AltArmy then return end

AltArmy.GraphLogic = AltArmy.GraphLogic or {}

local Logic = AltArmy.GraphLogic

Logic.FULL_LINE_ALPHA = 0.9
Logic.FULL_DASH_ALPHA = 0.55
Logic.FULL_MARKER_ALPHA = 1
Logic.DIM_LINE_ALPHA = 0.22
Logic.DIM_DASH_ALPHA = 0.14
Logic.DIM_MARKER_ALPHA = 0.35
Logic.LOG_AXIS_MAX_FLOOR_SECONDS = 300
Logic.LOG_Y_MIN_TICK_SPACING_FRACTION = 0.12
Logic.SECONDS_PER_DAY = 86400
Logic.LINEAR_Y_TARGET_TICKS = 4
Logic.LINEAR_Y_STEP_CANDIDATES = {
    5, 10, 15, 30,
    60, 120, 180, 300, 600, 900, 1800,
    2700, 3600, 5400, 7200, 10800, 14400, 21600, 43200, 86400,
}

local function BuildLogYStepCandidates()
    local candidates = {}
    for _, value in ipairs(Logic.LINEAR_Y_STEP_CANDIDATES) do
        candidates[#candidates + 1] = value
    end
    for exponent = 1, 8 do
        candidates[#candidates + 1] = Logic.SECONDS_PER_DAY * (2 ^ exponent)
    end
    return candidates
end

Logic.LOG_Y_STEP_CANDIDATES = BuildLogYStepCandidates()
Logic.OUTLIER_IQR_MULTIPLIER = 3
Logic.OUTLIER_MEDIAN_MULTIPLIER = 5
Logic.OUTLIER_TOP_DURATION_COUNT = 10
Logic.OUTLIER_TOP_MARGIN = 6
Logic.ROLLING_AVERAGE_WINDOW = 5
Logic.COMPARE_SELECT_ALL_MIN_COUNT = 4
-- Line colors for a second, third, ... selected character of the same class.
-- Chosen offline by greedy max-min OKLab distance from the nine class colors,
-- the chart backdrop and the neutral gray, so each is clearly unlike all of them
-- and each other (every pairwise distance is over DISTINCT_COLOR_DISTANCE; a
-- distance of 0.02 is about just noticeable, 0.1 a clearly different color).
-- At runtime AssignLineColors picks, per repeat, the one farthest from
-- everything already on the chart.
Logic.FALLBACK_LINE_COLORS = {
    { 0.90, 0.00, 0.98 }, -- magenta
    { 0.01, 0.64, 0.13 }, -- green
    { 0.95, 0.09, 0.37 }, -- crimson
    { 0.20, 0.59, 0.60 }, -- teal
    { 0.22, 1.00, 0.91 }, -- aqua
    { 0.15, 0.98, 0.26 }, -- lime
    { 0.70, 0.43, 0.57 }, -- mauve
    { 0.95, 0.77, 0.99 }, -- lavender
    { 0.99, 0.77, 0.58 }, -- peach
    { 0.19, 0.75, 0.55 }, -- sea green
}
-- Colors a line must also stand apart from: the chart backdrop (Theme's
-- sectionBg) and the neutral gray of an unknown class.
Logic.LINE_COLOR_AVOID = {
    { 0.08, 0.08, 0.10 },
    { 0.70, 0.70, 0.70 },
}
Logic.DISTINCT_COLOR_DISTANCE = 0.1

local function LinearizeChannel(c)
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function CubeRoot(x)
    if x <= 0 then return 0 end
    return x ^ (1 / 3)
end

--- Converts an sRGB color (0..1 channels) to OKLab, a perceptually uniform
--- space where Euclidean distance approximates how different two colors look.
--- @param r number
--- @param g number
--- @param b number
--- @return number L, number a, number b
function Logic.ToOklab(r, g, b)
    r, g, b = LinearizeChannel(r), LinearizeChannel(g), LinearizeChannel(b)
    local l = CubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    local m = CubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    local s = CubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

local function OklabDistance(p, q)
    local dl, da, db = p[1] - q[1], p[2] - q[2], p[3] - q[3]
    return math.sqrt(dl * dl + da * da + db * db)
end

--- Perceptual distance between two sRGB colors (OKLab Euclidean distance).
--- @return number
function Logic.ColorDistance(r1, g1, b1, r2, g2, b2)
    return OklabDistance({ Logic.ToOklab(r1, g1, b1) }, { Logic.ToOklab(r2, g2, b2) })
end

local fallbackOklab = nil

local function FallbackOklab()
    if not fallbackOklab then
        fallbackOklab = {}
        for i, c in ipairs(Logic.FALLBACK_LINE_COLORS) do
            fallbackOklab[i] = { Logic.ToOklab(c[1], c[2], c[3]) }
        end
    end
    return fallbackOklab
end

-- The untaken palette index whose nearest in-use color is farthest away
-- (ties to the lowest index, so the result is deterministic).
local function PickFarthest(used, taken)
    local bestIndex, bestScore = nil, -1
    for i, lab in ipairs(FallbackOklab()) do
        if not taken[i] then
            local nearest = math.huge
            for _, u in ipairs(used) do
                local d = OklabDistance(lab, u)
                if d < nearest then nearest = d end
            end
            if nearest > bestScore then
                bestIndex, bestScore = i, nearest
            end
        end
    end
    return bestIndex
end

--- Picks a line color for each selected character, in order. The first
--- character of each class keeps its class color; every later one gets the
--- fallback color farthest (in OKLab) from everything already on the chart:
--- the class colors present, the backdrop and the fallbacks picked before it.
--- Once every fallback is in use they are picked again, nearest-last.
--- @param entries table array of { classFile = string|nil, r, g, b }
--- @return table array of { r, g, b } parallel to entries
function Logic.AssignLineColors(entries)
    local out = {}
    local used = {}
    for _, c in ipairs(Logic.LINE_COLOR_AVOID) do
        used[#used + 1] = { Logic.ToOklab(c[1], c[2], c[3]) }
    end

    local seenClass = {}
    for i, e in ipairs(entries) do
        local key = e.classFile or ""
        if not seenClass[key] then
            seenClass[key] = true
            out[i] = { r = e.r, g = e.g, b = e.b }
            used[#used + 1] = { Logic.ToOklab(e.r, e.g, e.b) }
        end
    end

    local taken = {}
    for i = 1, #entries do
        if not out[i] then
            local index = PickFarthest(used, taken)
            if not index then
                taken = {}
                index = PickFarthest(used, taken)
            end
            taken[index] = true
            local c = Logic.FALLBACK_LINE_COLORS[index]
            out[i] = { r = c[1], g = c[2], b = c[3] }
            used[#used + 1] = FallbackOklab()[index]
        end
    end
    return out
end

--- A character's key in the Graph's saved selection: realm\storage key (the GUID,
--- or the name for an entry saved before GUIDs), so two characters of one name
--- stay apart; a linked account's carries its link, so it is never one of ours.
--- @param entry table { realm, name, key = string|nil, linkId = string|nil }
--- @return string
function Logic.SelectionKey(entry)
    local id = entry.key or entry.name or ""
    local key = (entry.realm or "") .. "\\" .. id
    if entry.linkId then
        key = key .. "\1" .. entry.linkId
    end
    return key
end

local function NameKey(entry)
    return Logic.SelectionKey({ realm = entry.realm, name = entry.name, linkId = entry.linkId })
end

--- Moves selections saved by name, before they were keyed by storage key, to the
--- key of every listed character of that name, in place. A name key matching no
--- listed character is left as it is.
--- @param selected table saved selection keys -> true
--- @param list table the compare list's entries
function Logic.MigrateNameSelections(selected, list)
    local migrated = {}
    for _, entry in ipairs(list) do
        local nameKey = NameKey(entry)
        local key = Logic.SelectionKey(entry)
        if key ~= nameKey and selected[nameKey] then
            selected[key] = true
            migrated[nameKey] = true
        end
    end
    for nameKey in pairs(migrated) do
        selected[nameKey] = nil
    end
end

function Logic.ShouldShowCompareSelectAll(characterCount)
    return characterCount > Logic.COMPARE_SELECT_ALL_MIN_COUNT
end

function Logic.IsCompareSelectAllChecked(characterCount, selectedCount)
    if characterCount <= 0 then
        return false
    end
    return selectedCount >= characterCount
end

function Logic.GetCompareSelectAllAction(allCurrentlySelected)
    return not allCurrentlySelected
end

function Logic.ComputeSeriesAlphas(dimOthers, isHovered)
    if not dimOthers then
        return Logic.FULL_LINE_ALPHA, Logic.FULL_DASH_ALPHA, Logic.FULL_MARKER_ALPHA
    end
    if isHovered then
        return Logic.FULL_LINE_ALPHA, Logic.FULL_DASH_ALPHA, Logic.FULL_MARKER_ALPHA
    end
    return Logic.DIM_LINE_ALPHA, Logic.DIM_DASH_ALPHA, Logic.DIM_MARKER_ALPHA
end

function Logic.HoverNeedsRebuild(
    hoveredKey, drawnKeys, hoveredMaxSeconds, currentRawYMax,
    hoveredMinSeconds, currentRawYMin, logarithmic
)
    if not hoveredKey then
        return false
    end
    if drawnKeys[hoveredKey] then
        return false
    end
    if logarithmic and hoveredMinSeconds and currentRawYMin and currentRawYMin > 0 then
        if hoveredMinSeconds < currentRawYMin then
            return true
        end
    end
    return hoveredMaxSeconds > currentRawYMax
end

local LOG10 = math.log(10)

local function Log10(value)
    return math.log(value) / LOG10
end

function Logic.ComputeLinearYGridTicks(yMin, yMax, targetCount)
    targetCount = targetCount or Logic.LINEAR_Y_TARGET_TICKS
    yMin = yMin or 0
    yMax = math.max(yMin + 1, yMax or 1)
    local range = yMax - yMin
    local rawStep = range / targetCount
    local minStep = rawStep * 0.85

    local step = Logic.LINEAR_Y_STEP_CANDIDATES[#Logic.LINEAR_Y_STEP_CANDIDATES]
    for _, candidate in ipairs(Logic.LINEAR_Y_STEP_CANDIDATES) do
        if candidate >= minStep then
            step = candidate
            break
        end
    end

    local top = math.ceil(yMax / step) * step
    local ticks = {}
    if yMin <= 0.001 then
        ticks[#ticks + 1] = 0
        local val = step
        while val <= top + 0.001 do
            ticks[#ticks + 1] = val
            val = val + step
        end
        return ticks, top
    end

    local val = math.ceil(yMin / step) * step
    while val <= top + 0.001 do
        ticks[#ticks + 1] = val
        val = val + step
    end
    return ticks, top
end

function Logic.ComputeLinearYAxis(rawYMax, targetTickCount)
    local yPad = math.max(1, math.floor(rawYMax * 0.08))
    local yMin = 0
    local dataMax = math.max(1, rawYMax + yPad)
    local gridTicks, top = Logic.ComputeLinearYGridTicks(yMin, dataMax, targetTickCount)
    local paddedYMax = top
    local yRange = math.max(1, paddedYMax - yMin)
    return {
        yMin = yMin,
        paddedYMax = paddedYMax,
        yRange = yRange,
        gridTicks = gridTicks,
    }
end

local function LargestDurationCandidateBelow(value)
    local best = 1
    for _, candidate in ipairs(Logic.LOG_Y_STEP_CANDIDATES) do
        if candidate < value and candidate > best then
            best = candidate
        end
    end
    return math.max(1, best)
end

local function CeilingDurationCandidate(value)
    for _, candidate in ipairs(Logic.LOG_Y_STEP_CANDIDATES) do
        if candidate >= value then
            return candidate
        end
    end
    return value
end

function Logic.ComputeLogAxisFloor(rawYMin, ignoreMaxFloor)
    if not rawYMin or rawYMin <= 1 then
        return 1
    end

    local best = LargestDurationCandidateBelow(rawYMin)
    if ignoreMaxFloor then
        return best
    end
    return math.min(Logic.LOG_AXIS_MAX_FLOOR_SECONDS, best)
end

local function ComputeLogYGridTicks(yMin, paddedYMax)
    local gridTicks = {}
    for _, val in ipairs(Logic.LOG_Y_STEP_CANDIDATES) do
        if val >= yMin and val <= paddedYMax then
            gridTicks[#gridTicks + 1] = val
        end
    end

    table.sort(gridTicks)
    if #gridTicks == 0 or gridTicks[1] ~= yMin then
        table.insert(gridTicks, 1, yMin)
    end
    return gridTicks
end

--- Greedy filter: keep the bottom tick, then each next tick only if it is far
--- enough above the last kept tick on the log scale (fraction of axis height).
--- @param ticks table array of second values in ascending order
--- @param logMin number log10 of axis floor
--- @param logMax number log10 of axis ceiling
--- @param minSpacingFraction number minimum vertical gap as a 0–1 fraction
--- @return table filtered ticks for display
function Logic.FilterLogYGridTicks(ticks, logMin, logMax, minSpacingFraction)
    if not ticks or #ticks == 0 then
        return {}
    end
    if #ticks == 1 then
        return { ticks[1] }
    end

    local logRange = logMax - logMin
    if logRange <= 0 then
        return { ticks[1] }
    end

    local function logFraction(val)
        return (Log10(val) - logMin) / logRange
    end

    local filtered = { ticks[1] }
    local lastKeptFrac = logFraction(ticks[1])

    for i = 2, #ticks do
        local val = ticks[i]
        local frac = logFraction(val)
        if frac - lastKeptFrac >= minSpacingFraction then
            filtered[#filtered + 1] = val
            lastKeptFrac = frac
        end
    end

    return filtered
end

function Logic.ComputeLogYAxis(rawYMax, rawYMin, ignoreMaxFloor)
    local yPad = math.max(1, math.floor(rawYMax * 0.08))
    local dataMax = math.max(1, rawYMax + yPad)
    local yMin = Logic.ComputeLogAxisFloor(rawYMin, ignoreMaxFloor)
    local paddedYMax = CeilingDurationCandidate(dataMax)
    local logMin = Log10(yMin)
    local logMax = Log10(paddedYMax)

    return {
        yMin = yMin,
        paddedYMax = paddedYMax,
        logMin = logMin,
        logMax = logMax,
        gridTicks = ComputeLogYGridTicks(yMin, paddedYMax),
    }
end

--- Leading-gap interpolation modes.
--- linear: Y interpolates straight from 0 to end (time-per-level dashed approx).
--- quadratic: Y = end * frac^2 — integral of a linear time-per-level ramp from 0 to 2R
--- (average rate R), so cumulative play time bows below the straight chord.
Logic.LEADING_GAP_CURVE_LINEAR = "linear"
Logic.LEADING_GAP_CURVE_QUADRATIC = "quadratic"

--- Sample the dashed leading-gap path in data space.
--- @param gap table { fromLevel, ... }
--- @param endPt table { level, seconds }
--- @param pointCount number|nil
--- @param axisFloor number|nil log-axis floor to clip the start against
--- @param curveMode string|nil Logic.LEADING_GAP_CURVE_LINEAR or _QUADRATIC
--- @return table[] { level, seconds }
function Logic.SampleLeadingGapCurve(gap, endPt, pointCount, axisFloor, curveMode)
    pointCount = pointCount or 24
    local fromLevel = gap.fromLevel
    local toLevel = endPt.level
    local endSeconds = endPt.seconds
    local levelSpan = toLevel - fromLevel
    local quadratic = curveMode == Logic.LEADING_GAP_CURVE_QUADRATIC
    if levelSpan <= 0 then
        return {
            { level = fromLevel, seconds = 0 },
            { level = toLevel, seconds = endSeconds },
        }
    end

    local function SecondsAtFrac(frac)
        if quadratic then
            return endSeconds * frac * frac
        end
        return endSeconds * frac
    end

    local startFrac = 0
    if axisFloor and axisFloor > 0 and endSeconds > axisFloor then
        if quadratic then
            startFrac = math.sqrt(axisFloor / endSeconds)
        else
            startFrac = axisFloor / endSeconds
        end
    end

    local startLevel = fromLevel + startFrac * levelSpan
    local startSeconds = SecondsAtFrac(startFrac)
    local spanFrac = 1 - startFrac

    local samples = {}
    for i = 0, pointCount do
        local frac = startFrac + (i / pointCount) * spanFrac
        samples[#samples + 1] = {
            level = fromLevel + frac * levelSpan,
            seconds = SecondsAtFrac(frac),
        }
    end

    -- Keep exact endpoints after float math.
    samples[1].level = startLevel
    samples[1].seconds = startSeconds
    samples[#samples].level = toLevel
    samples[#samples].seconds = endSeconds
    return samples
end

local function CopySeriesPoint(pt)
    return {
        level = pt.level,
        seconds = pt.seconds,
        fromLevel = pt.fromLevel,
        toLevel = pt.toLevel,
        totalSeconds = pt.totalSeconds,
        spansGap = pt.spansGap,
        isOutlier = false,
    }
end

local function Percentile(sorted, p)
    local n = #sorted
    if n == 0 then
        return 0
    end
    if n == 1 then
        return sorted[1]
    end

    local index = (n - 1) * p + 1
    local lo = math.floor(index)
    local hi = math.ceil(index)
    if lo == hi then
        return sorted[lo]
    end
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (index - lo)
end

function Logic.IsExtremeOutlier(seconds, allSeconds)
    if not seconds or seconds <= 0 or not allSeconds or #allSeconds < 3 then
        return false
    end

    local sorted = {}
    for _, value in ipairs(allSeconds) do
        sorted[#sorted + 1] = value
    end
    table.sort(sorted)

    local q1 = Percentile(sorted, 0.25)
    local q3 = Percentile(sorted, 0.75)
    local iqr = q3 - q1
    if iqr > 0 then
        return seconds > q3 + Logic.OUTLIER_IQR_MULTIPLIER * iqr
    end

    local median = Percentile(sorted, 0.5)
    return seconds > median * Logic.OUTLIER_MEDIAN_MULTIPLIER
end

function Logic.GetTopDurationPointIndices(points, count)
    count = count or Logic.OUTLIER_TOP_DURATION_COUNT
    local ranked = {}
    for i, pt in ipairs(points) do
        ranked[#ranked + 1] = {
            index = i,
            seconds = pt.seconds or 0,
        }
    end

    table.sort(ranked, function(a, b)
        if a.seconds ~= b.seconds then
            return a.seconds > b.seconds
        end
        return a.index < b.index
    end)

    local indices = {}
    local limit = math.min(count, #ranked)
    for i = 1, limit do
        indices[ranked[i].index] = true
    end
    return indices
end

function Logic.BuildShrunkVirtualSeconds(points)
    local virtual = {}
    local _, shrunkMax = Logic.GetSeriesScaleBounds(points, true)

    for i, pt in ipairs(points) do
        if pt.isOutlier and shrunkMax > 0 then
            virtual[i] = shrunkMax
        else
            virtual[i] = pt.seconds or 0
        end
    end

    return virtual
end

function Logic.ApplyRollingAverage(points, windowSize, shrinkOutliers)
    if not points or #points == 0 then
        return {}
    end

    windowSize = windowSize or Logic.ROLLING_AVERAGE_WINDOW
    if windowSize <= 1 then
        local unchanged = {}
        for _, pt in ipairs(points) do
            unchanged[#unchanged + 1] = CopySeriesPoint(pt)
        end
        return unchanged
    end

    local virtualSeconds = shrinkOutliers and Logic.BuildShrunkVirtualSeconds(points) or nil
    local half = math.floor(windowSize / 2)
    local smoothed = {}

    for i, pt in ipairs(points) do
        local copy = CopySeriesPoint(pt)
        local sum = 0
        local count = 0
        local fromIndex = math.max(1, i - half)
        local toIndex = math.min(#points, i + half)

        for j = fromIndex, toIndex do
            local value = virtualSeconds and virtualSeconds[j] or (points[j].seconds or 0)
            sum = sum + value
            count = count + 1
        end

        if count > 0 then
            copy.seconds = sum / count
        end
        copy.isOutlier = false
        smoothed[#smoothed + 1] = copy
    end

    return smoothed
end

function Logic.ApplyOutlierFlags(points, ignoreOutliers)
    local marked = {}

    for _, pt in ipairs(points) do
        marked[#marked + 1] = CopySeriesPoint(pt)
    end

    if not ignoreOutliers then
        return marked
    end

    local topDurationIndices = Logic.GetTopDurationPointIndices(marked)
    local topDurationSeconds = {}
    for i, pt in ipairs(marked) do
        if topDurationIndices[i] and pt.seconds and pt.seconds > 0 then
            topDurationSeconds[#topDurationSeconds + 1] = pt.seconds
        end
    end

    for i, pt in ipairs(marked) do
        if topDurationIndices[i] then
            pt.isOutlier = Logic.IsExtremeOutlier(pt.seconds, topDurationSeconds)
        end
    end

    return marked
end

function Logic.BuildSeriesDrawPlan(points)
    local segments = {}
    local markers = {}
    local lastNormalIdx = nil

    for _, pt in ipairs(points) do
        markers[#markers + 1] = { pt = pt }
    end

    for i, pt in ipairs(points) do
        if pt.isOutlier then
            if lastNormalIdx and i == lastNormalIdx + 1 then
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[lastNormalIdx],
                    to = pt,
                    isOutlierSpike = true,
                }
            elseif i > 1 and points[i - 1].isOutlier then
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[i - 1],
                    to = pt,
                    isOutlierSpike = true,
                }
            end
        elseif lastNormalIdx then
            if i > lastNormalIdx + 1 then
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[i - 1],
                    to = pt,
                    isOutlierReturn = true,
                }
            else
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[lastNormalIdx],
                    to = pt,
                }
            end
            lastNormalIdx = i
        else
            lastNormalIdx = i
        end
    end

    return { segments = segments, markers = markers }
end

function Logic.ComputePlotTopY(plotH, padding, margin)
    padding = padding or { bottom = 28 }
    margin = margin or Logic.OUTLIER_TOP_MARGIN
    return padding.bottom + plotH - margin
end

function Logic.PlotSeriesPoint(pt, x, y, plotTopY)
    if pt.isOutlier then
        return x, math.min(y, plotTopY)
    end
    return x, y
end

function Logic.GetSeriesScaleBounds(points, ignoreOutliers, minLevel, maxLevel)
    local yMax = 0
    local yMin = math.huge
    local filterByLevel = minLevel ~= nil and maxLevel ~= nil

    for _, pt in ipairs(points) do
        if not filterByLevel or (pt.level >= minLevel and pt.level <= maxLevel) then
            if not ignoreOutliers or not pt.isOutlier then
                if pt.seconds and pt.seconds > 0 and pt.seconds < yMin then
                    yMin = pt.seconds
                end
                if pt.seconds and pt.seconds > yMax then
                    yMax = pt.seconds
                end
            end
        end
    end

    if yMin == math.huge then
        yMin = 0
    end
    return yMin, yMax
end

function Logic.ChooseXLabelInterval(xRange)
    if xRange <= 5 then
        return 1
    end
    if xRange <= 12 then
        return 2
    end
    if xRange <= 30 then
        return 5
    end
    return 10
end

function Logic.NormalizeZoomRange(a, b, fullMin, fullMax, minSpan)
    minSpan = minSpan or 2
    local lo = math.floor(math.min(a, b) + 0.5)
    local hi = math.floor(math.max(a, b) + 0.5)
    lo = math.max(fullMin, lo)
    hi = math.min(fullMax, hi)
    if hi - lo < minSpan then
        return nil
    end
    return lo, hi
end

local function CopyPointForClip(pt)
    return {
        level = pt.level,
        seconds = pt.seconds,
        fromLevel = pt.fromLevel,
        toLevel = pt.toLevel,
        totalSeconds = pt.totalSeconds,
        spansGap = pt.spansGap,
        isOutlier = pt.isOutlier,
    }
end

local function InterpolatePointAtLevel(fromPt, toPt, level)
    local levelSpan = toPt.level - fromPt.level
    if levelSpan <= 0 then
        return CopyPointForClip(fromPt)
    end

    local frac = (level - fromPt.level) / levelSpan
    local seconds = fromPt.seconds + frac * (toPt.seconds - fromPt.seconds)
    local copy = CopyPointForClip(fromPt)
    copy.level = level
    copy.seconds = seconds
    return copy
end

local function ClipSegmentToRange(fromPt, toPt, minLevel, maxLevel)
    local loLevel = fromPt.level
    local hiLevel = toPt.level
    if loLevel > hiLevel then
        loLevel, hiLevel = hiLevel, loLevel
        fromPt, toPt = toPt, fromPt
    end

    if hiLevel < minLevel or loLevel > maxLevel then
        return nil
    end

    local clippedFrom = fromPt
    local clippedTo = toPt

    if clippedFrom.level < minLevel then
        clippedFrom = InterpolatePointAtLevel(fromPt, toPt, minLevel)
    end
    if clippedTo.level > maxLevel then
        clippedTo = InterpolatePointAtLevel(fromPt, toPt, maxLevel)
    end

    if clippedFrom.level == clippedTo.level and clippedFrom.seconds == clippedTo.seconds then
        return nil
    end

    return clippedFrom, clippedTo
end

function Logic.ClipDrawPlanToRange(drawPlan, minLevel, maxLevel)
    local clippedSegments = {}
    local clippedMarkers = {}

    for _, marker in ipairs(drawPlan.markers or {}) do
        local pt = marker.pt
        if pt and pt.level >= minLevel and pt.level <= maxLevel then
            clippedMarkers[#clippedMarkers + 1] = { pt = pt }
        end
    end

    for _, seg in ipairs(drawPlan.segments or {}) do
        local fromPt = seg.from
        local toPt = seg.to
        if fromPt and toPt then
            local clippedFrom, clippedTo = ClipSegmentToRange(fromPt, toPt, minLevel, maxLevel)
            if clippedFrom and clippedTo then
                clippedSegments[#clippedSegments + 1] = {
                    style = seg.style,
                    from = clippedFrom,
                    to = clippedTo,
                    isOutlierSpike = seg.isOutlierSpike,
                    isOutlierReturn = seg.isOutlierReturn,
                }
            end
        end
    end

    return { segments = clippedSegments, markers = clippedMarkers }
end

function Logic.YToFraction(y, axis, logarithmic)
    if logarithmic then
        local clamped = math.max(y, axis.yMin)
        local logY = Log10(clamped)
        local logRange = axis.logMax - axis.logMin
        if logRange <= 0 then
            return 0
        end
        return (logY - axis.logMin) / logRange
    end

    if axis.yRange <= 0 then
        return 0
    end
    return (y - axis.yMin) / axis.yRange
end
