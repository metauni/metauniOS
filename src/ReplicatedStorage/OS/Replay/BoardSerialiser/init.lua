local FigureSerialiser = require(script.FigureSerialiser)

local function serialise(figures, nextFigureZIndex, surfaceCFrame, surfaceSize)

	local entries = {}

	for figureId, figure in pairs(figures) do

		if FigureSerialiser.FullyMasked(figure) then

			continue
		end

		local serialisedFigure = FigureSerialiser.Serialise(figure)

		table.insert(entries, { figureId, serialisedFigure })
	end

	return {

		FigureEntries = entries,
		NextFigureZIndex = nextFigureZIndex,
		SurfaceCFrame = {surfaceCFrame:GetComponents()},
		SurfaceSize = {surfaceSize.X, surfaceSize.Y},
	}
end

local function deserialise(data)

	local figures = {}

	for _, entry in ipairs(data.FigureEntries) do

		local figureId, serialisedFigure = unpack(entry)

		local figure = FigureSerialiser.Deserialise(serialisedFigure)
		-- TODO: add to erase grid?

		figures[figureId] = figure
	end

	return figures, data.NextFigureZIndex, CFrame.new(unpack(data.SurfaceCFrame)), Vector2.new(unpack(data.SurfaceSize))
end

return {

	Serialise = serialise,
	Deserialise = deserialise,
}