--!strict

-- Buslock explorer
-- I made it quickly (in 2 hours), so I didn't put much effort into refactoring it
-- It's complicated yet at the same time basic
-- It's quick, but at the same time it doesn't update the gui when a new child is added or an instance is destroyed

-- FEATURES:
-- - expand and contract
-- - explorer names do update
-- - UI reflects removed items and added items
-- - able to drag the GUI
-- - proper disconnection of signals when the script is ran again or closed
-- - fast

if _G.buslock_quit then
	_G.buslock_quit()
	_G.buslock_quit = nil
end

-- Linked list implementation to store currently visible in the GUI game instances
type ExplorerNode = {
	instance: Instance,

	-- ui related
	indentation: number,
	expanded: boolean,
	last_item_associated: ExplorerUIItem?, -- I put this here just to implement a clever trick to check if this node is currently visible in the GUI. useful to reduce some GUI updates. explained in `update_explorer_ui`
	removed: boolean, -- This will give the item a red color
	recently_added: boolean, -- This will give the item a green color -- TODO: merge `recently_added` and `removed` into a single variable. because they just represent three states: normal node, removed node, and recently added node. so they should all be together with an enum or smt

	-- reference to the nodes
	-- this will allow us to do many kind of operations quickly
	-- at the cost of a complicated implementation
	child: ExplorerNode?,	-- sidenote: if child is nil, then it means that
	-- this node wasn't expanded (via UI)
	-- so, if nil: node isn't expanded
	-- if not nil: node is expanded and should render childs
	last_child: ExplorerNode?,
	next: ExplorerNode?,
	back: ExplorerNode?,
	parent: ExplorerNode?
}

local function new_node(instance: Instance): ExplorerNode
	local node: ExplorerNode = {
		instance = instance,
		indentation = 0,
		expanded = false,
		removed = false,
		recently_added = false,
	}

	return node
end

local function new_child_node(instance: Instance, parent: ExplorerNode): ExplorerNode
	local node: ExplorerNode = {
		instance = instance,
		indentation = parent.indentation + 1,
		expanded = false,
		removed = parent.removed,
		recently_added = parent.recently_added,
		parent = parent,
		back = parent.last_child
	}
	if parent.last_child then
		parent.last_child.next = node
	end
	if not parent.child then
		parent.child = node
	end
	parent.last_child = node

	return node
end

local function contract_node(node: ExplorerNode)
	node.child = nil
	node.last_child = nil
end

local function get_next_node(node: ExplorerNode): ExplorerNode?
	local ret = node.expanded and node.child or node.next
	if ret then
		return ret
	end

	local cur_node: ExplorerNode? = node.parent
	while cur_node do
		if cur_node and cur_node.next then
			return cur_node.next
		end
		cur_node = cur_node.parent
	end

	return nil
end

local function get_prev_node(node: ExplorerNode): ExplorerNode?
	if node.back then
		local cur_node: ExplorerNode = node.back
		while cur_node.expanded and cur_node.last_child do
			cur_node = cur_node.last_child
		end

		return cur_node
	end

	if node.parent then
		return node.parent
	end

	return nil
end

-- gui
local connections: {[any]: RBXScriptConnection} = {}
local lp = game:GetService("Players").LocalPlayer

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Name = "Buslock"
xpcall(
	function()
		gui.Parent = game:GetService("CoreGui")
	end,
	function()
		gui.Parent = lp.PlayerGui
	end
)

function _G.buslock_quit()
	gui:Destroy()

	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
end

local function round_corners(instance: Instance): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = instance

	return corner
end

local function add_padding(instance: Instance, left: number, top: number, right: number, bottom: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.Parent = instance

	return padding
end

local topbar_color = Color3.fromRGB(40, 40, 40)
local topbartext_color = Color3.fromRGB(255, 255, 255)
local topbartext_selected_color = Color3.fromRGB(212, 244, 255)
local background_color = Color3.fromRGB(252, 252, 252)
local background_outline = Color3.fromRGB(222, 222, 222)
local background_textcolor = Color3.fromRGB(0, 0, 0)
local item_selected = Color3.fromRGB(104, 148, 217)
local item_selected_border = Color3.fromRGB(80, 115, 168)
local item_selected_border = Color3.fromRGB(80, 115, 168)
local item_selected_textcolor = Color3.fromRGB(255, 255, 255)
local item_deleted = Color3.fromRGB(232, 48, 51)
local item_deleted_selected = Color3.fromRGB(255, 53, 56)
local item_deleted_border = Color3.fromRGB(170, 35, 40)
local item_deleted_textcolor = Color3.fromRGB(255, 255, 255)
local item_added = Color3.fromRGB(46, 191, 24)
local item_added_selected = Color3.fromRGB(55, 229, 29)
local item_added_border = Color3.fromRGB(47, 184, 22)
local item_added_textcolor = Color3.fromRGB(255, 255, 255)

local topbar_size = 30
local explorer_size = 400
local ui_width = 300

local background = Instance.new("Frame")
background.Position = UDim2.fromOffset(10, 10)
background.Size = UDim2.fromOffset(ui_width, explorer_size + topbar_size)
background.ClipsDescendants = true
background.BackgroundColor3 = background_color
round_corners(background)
background.Parent = gui

do
	local stroke = Instance.new("UIStroke")
	stroke.Color = topbar_color
	stroke.Parent = background

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = background
end

local topbar = Instance.new("Frame")
topbar.Size = UDim2.new(1, 0, 0, topbar_size)
topbar.BackgroundColor3 = topbar_color
round_corners(topbar)
topbar.Parent = background

local topbar_square_corners = Instance.new("Frame")
topbar_square_corners.Size = UDim2.fromScale(1, 0.5)
topbar_square_corners.Position = UDim2.fromScale(0, 0.5)
topbar_square_corners.BorderSizePixel = 0
topbar_square_corners.BackgroundColor3 = topbar_color
topbar_square_corners.Parent = topbar

local topbartitle = Instance.new("TextLabel")
topbartitle.TextXAlignment = Enum.TextXAlignment.Left
topbartitle.Font = Enum.Font.Ubuntu
topbartitle.BackgroundTransparency = 1
topbartitle.Size = UDim2.fromScale(0.5, 1)
topbartitle.TextSize = 14
topbartitle.TextColor3 = topbartext_color
add_padding(topbartitle, 10, 0, 0, 0)
topbartitle.Parent = topbar

local topbar_button_width = 20
local ui_expanded = true
local hidebutton: ImageButton;
local closebutton: ImageButton;

do
	local padding = 5

	closebutton = Instance.new("ImageButton")
	closebutton.Size = UDim2.new(0, topbar_button_width, 1, -padding * 2)
	closebutton.AnchorPoint = Vector2.new(1, 0.5)
	closebutton.Position = UDim2.new(1, -padding, 0.5, 0)
	closebutton.Image = "http://www.roblox.com/asset/?id=10830675223"
	closebutton.BackgroundTransparency = 1
	closebutton.Parent = topbar

	hidebutton = Instance.new("ImageButton")
	hidebutton.Size = UDim2.new(0, topbar_button_width, 1, -padding * 2)
	hidebutton.AnchorPoint = Vector2.new(1, 0.5)
	hidebutton.Position = UDim2.new(1, -padding -topbar_button_width -padding, 0.5, 0)
	hidebutton.Image = "http://www.roblox.com/asset/?id=6972508944"
	hidebutton.BackgroundTransparency = 1
	hidebutton.Parent = topbar

	table.insert(connections,
		hidebutton.Activated:Connect(function()
			ui_expanded = not ui_expanded
			if ui_expanded then
				background.Size = UDim2.fromOffset(ui_width, topbar_size + explorer_size)
				topbar_square_corners.Visible = true
			else
				background.Size = UDim2.fromOffset(ui_width, topbar_size)
				topbar_square_corners.Visible = false
			end
		end)
	)

	table.insert(connections,
		closebutton.Activated:Connect(_G.buslock_quit)
	)
end

local explorerframe = Instance.new("Frame")
explorerframe.Size = UDim2.new(1, 0, 0, explorer_size)
explorerframe.Position = UDim2.fromOffset(0, topbar_size)
explorerframe.BackgroundTransparency = 1
explorerframe.Parent = topbar

do
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = explorerframe
end

-- dragging
do
	local dragging = false
	local mouse = lp:GetMouse()

	table.insert(connections,
		topbar.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			local originX = mouse.X - background.AbsolutePosition.X
			local originY = mouse.Y - background.AbsolutePosition.Y

			dragging = true
			while dragging do
				background.Position = UDim2.fromOffset(mouse.X - originX, mouse.Y - originY)
				task.wait()
			end
		end)
	)

	table.insert(connections,
		topbar.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			dragging = false
		end)
	)
end

-- explorer gui

-- TODO: finish this
local default_icon_index = Vector2.new(0, 0)
local icons_index: {[string]: Vector2} = {
	Part = Vector2.new(16, 0);
	WedgePart = Vector2.new(16, 0);
	TrussPart = Vector2.new(16, 0);
	RightAngleRampPart = Vector2.new(16, 0);
	PyramidPart = Vector2.new(16, 0);
	CornerWedgePart = Vector2.new(16, 0);
	PrismPart = Vector2.new(16, 0);
	ParallelRampPart = Vector2.new(16, 0);
	Model = Vector2.new(32, 0);
	Status = Vector2.new(32, 0);
	DoubleConstrainedValue = Vector2.new(64, 0);
	BrickColorValue = Vector2.new(64, 0);
	ObjectValue = Vector2.new(64, 0);
	Vector3Value = Vector2.new(64, 0);
	NumberValue = Vector2.new(64, 0);
	Color3Value = Vector2.new(64, 0);
	BinaryStringValue = Vector2.new(64, 0);
	TextureTrail = Vector2.new(64, 0);
	CFrameValue = Vector2.new(64, 0);
	StringValue = Vector2.new(64, 0);
	IntValue = Vector2.new(64, 0);
	FloorWire = Vector2.new(64, 0);
	CustomEvent = Vector2.new(64, 0);
	RayValue = Vector2.new(64, 0);
	BoolValue = Vector2.new(64, 0);
	CustomEventReceiver = Vector2.new(64, 0);
	IntConstrainedValue = Vector2.new(64, 0);
	Camera = Vector2.new(80, 0);
	Script = Vector2.new(96, 0);
	Decal = Vector2.new(112, 0);
	CylinderMesh = Vector2.new(128, 0);
	FileMesh = Vector2.new(128, 0);
	SpecialMesh = Vector2.new(128, 0);
	BlockMesh = Vector2.new(128, 0);
	Humanoid = Vector2.new(144, 0);
	Texture = Vector2.new(160, 0);
	Sound = Vector2.new(176, 0);
	Player = Vector2.new(192, 0);
	SurfaceLight = Vector2.new(208, 0);
	SpotLight = Vector2.new(208, 0);
	PointLight = Vector2.new(208, 0);
	Lighting = Vector2.new(208, 0);
	BodyVelocity = Vector2.new(224, 0);
	BodyThrust = Vector2.new(224, 0);
	BodyForce = Vector2.new(224, 0);
	BodyGyro = Vector2.new(224, 0);
	RocketPropulsion = Vector2.new(224, 0);
	BodyAngularVelocity = Vector2.new(224, 0);
	BodyPosition = Vector2.new(224, 0);
	NetworkServer = Vector2.new(240, 0);
	NetworkClient = Vector2.new(256, 0);
	Tool = Vector2.new(272, 0);
	LocalScript = Vector2.new(288, 0);
	CoreScript = Vector2.new(288, 0);
	Workspace = Vector2.new(304, 0);
	GamePassService = Vector2.new(304, 0);
	StarterPack = Vector2.new(320, 0);
	StarterGear = Vector2.new(320, 0);
	Backpack = Vector2.new(320, 0);
	Players = Vector2.new(336, 0);
	HopperBin = Vector2.new(352, 0);
	Teams = Vector2.new(368, 0);
	Team = Vector2.new(384, 0);
	SpawnLocation = Vector2.new(400, 0);
	Sky = Vector2.new(448, 0);
	NetworkReplicator = Vector2.new(464, 0);
	CollectionService = Vector2.new(480, 0);
	Debris = Vector2.new(480, 0);
	SoundService = Vector2.new(496, 0);
	Accessory = Vector2.new(512, 0);
	Accoutrement = Vector2.new(512, 0);
	Chat = Vector2.new(528, 0);
	Message = Vector2.new(528, 0);
	Hint = Vector2.new(528, 0);
	Glue = Vector2.new(544, 0);
	JointsService = Vector2.new(544, 0);
	Motor = Vector2.new(544, 0);
	Rotate = Vector2.new(544, 0);
	Attachment = Vector2.new(544, 0);
	Motor6D = Vector2.new(544, 0);
	Snap = Vector2.new(544, 0);
	RotateV = Vector2.new(544, 0);
	RotateP = Vector2.new(544, 0);
	VelocityMotor = Vector2.new(544, 0);
	Weld = Vector2.new(544, 0);
	JointInstance = Vector2.new(544, 0);
	VehicleSeat = Vector2.new(560, 0);
	Seat = Vector2.new(560, 0);
	SkateboardPlatform = Vector2.new(560, 0);
	Platform = Vector2.new(560, 0);
	Explosion = Vector2.new(576, 0);
	TouchTransmitter = Vector2.new(592, 0);
	ForceField = Vector2.new(592, 0);
	PathfindingService = Vector2.new(592, 0);
	Flag = Vector2.new(608, 0);
	FlagStand = Vector2.new(624, 0);
	ShirtGraphic = Vector2.new(640, 0);
	ContextActionService = Vector2.new(656, 0);
	ClickDetector = Vector2.new(656, 0);
	Sparkles = Vector2.new(672, 0);
	Shirt = Vector2.new(688, 0);
	Pants = Vector2.new(704, 0);
	Hat = Vector2.new(720, 0);
	StarterGui = Vector2.new(736, 0);
	MarketplaceService = Vector2.new(736, 0);
	CoreGui = Vector2.new(736, 0);
	PlayerGui = Vector2.new(736, 0);
	GuiService = Vector2.new(752, 0);
	ScreenGui = Vector2.new(752, 0);
	GuiMain = Vector2.new(752, 0);
	Frame = Vector2.new(768, 0);
	ScrollingFrame = Vector2.new(768, 0);
	ImageLabel = Vector2.new(784, 0);
	TextLabel = Vector2.new(800, 0);
	TextBox = Vector2.new(816, 0);
	TextButton = Vector2.new(816, 0);
	GuiButton = Vector2.new(832, 0);
	ImageButton = Vector2.new(832, 0);
	Handles = Vector2.new(848, 0);
	BoxHandleAdornment = Vector2.new(864, 0);
	CylinderHandleAdornment = Vector2.new(864, 0);
	SelectionBox = Vector2.new(864, 0);
	SphereHandleAdornment = Vector2.new(864, 0);
	ConeHandleAdornment = Vector2.new(864, 0);
	LineHandleAdornment = Vector2.new(864, 0);
	SelectionSphere = Vector2.new(864, 0);
	Selection = Vector2.new(880, 0);
	SurfaceSelection = Vector2.new(880, 0);
	ArcHandles = Vector2.new(896, 0);
	SelectionPartLasso = Vector2.new(912, 0);
	PartPairLasso = Vector2.new(912, 0);
	SelectionPointLasso = Vector2.new(912, 0);
	Configuration = Vector2.new(928, 0);
	Smoke = Vector2.new(944, 0);
	Pose = Vector2.new(960, 0);
	AnimationController = Vector2.new(960, 0);
	CharacterMesh = Vector2.new(960, 0);
	Keyframe = Vector2.new(960, 0);
	AnimationTrack = Vector2.new(960, 0);
	KeyframeSequence = Vector2.new(960, 0);
	Animation = Vector2.new(960, 0);
	Animator = Vector2.new(960, 0);
	KeyframeSequenceProvider = Vector2.new(960, 0);
	Fire = Vector2.new(976, 0);
	Dialog = Vector2.new(992, 0);
	DialogChoice = Vector2.new(1008, 0);
	BillboardGui = Vector2.new(1024, 0);
	SurfaceGui = Vector2.new(1024, 0);
	TerrainRegion = Vector2.new(1040, 0);
	Terrain = Vector2.new(1040, 0);
	RunService = Vector2.new(1056, 0);
	BindableFunction = Vector2.new(1056, 0);
	BindableEvent = Vector2.new(1072, 0);
	TestService = Vector2.new(1088, 0);
	ParticleEmitter = Vector2.new(1280, 0);
	Folder = Vector2.new(1232, 0);
	ModuleScript = Vector2.new(1216, 0);
	ReplicatedFirst = Vector2.new(1120, 0);
	ReplicatedStorage = Vector2.new(1120, 0);
	UnionOperation = Vector2.new(1168, 0);
	NegateOperation = Vector2.new(1152, 0);
	RemoteFunction = Vector2.new(1184, 0);
	RemoteEvent = Vector2.new(1200, 0);
	StarterPlayerScripts = Vector2.new(1248, 0);
	StarterCharacterScripts = Vector2.new(1248, 0);
	PlayerScripts = Vector2.new(1248, 0);
	StarterPlayer = Vector2.new(1264, 0);
}

type ExplorerNodeLookup = {[Instance]: ExplorerNode} -- value references should be weak!

type ExplorerUI = {
	node: ExplorerNode,
	items: {ExplorerUIItem},
	node_lookup: ExplorerNodeLookup,
	should_update_ui: boolean -- this should be handled externally
	-- something should detect when ExplorerUI.should_update_ui becomes true and update the UI
	-- this is to avoid updating the UI multiple times a frame
}

type ExplorerUIItem = {
	frame: Frame,
	padding: UIPadding,
	instname: TextButton,
	expandicon: ImageLabel,
	classicon: ImageLabel,
	node: ExplorerNode?,
	
	update_to_node: (node: ExplorerNode) -> (),
	show: () -> (),
	hide: () -> (),
	
	update_name_event: RBXScriptConnection?
}

local function add_to_lookup(lookup: ExplorerNodeLookup, node: ExplorerNode)
	lookup[node.instance] = node
end

local function color_item(item: ExplorerUIItem)
	if item.node and item.node.removed then
		item.frame.BackgroundColor3 = item_deleted
		item.frame.BorderColor3 = item_deleted_border
		item.instname.TextColor3 = item_deleted_textcolor
		return
	end

	if item.node and item.node.recently_added then
		item.frame.BackgroundColor3 = item_added
		item.frame.BorderColor3 = item_added_border
		item.instname.TextColor3 = item_added_textcolor
		return
	end

	item.frame.BackgroundColor3 = background_color
	item.frame.BorderColor3 = background_outline
	item.instname.TextColor3 = background_textcolor
end

local function color_hovered_item(item: ExplorerUIItem)
	if item.node and item.node.removed then
		item.frame.BackgroundColor3 = item_deleted_selected
		item.frame.BorderColor3 = item_deleted_border
		item.instname.TextColor3 = item_deleted_textcolor
		return
	end

	if item.node and item.node.recently_added then
		item.frame.BackgroundColor3 = item_added_selected
		item.frame.BorderColor3 = item_added_border
		item.instname.TextColor3 = item_added_textcolor
		return
	end

	item.frame.BackgroundColor3 = item_selected
	item.frame.BorderColor3 = item_selected_border
	item.instname.TextColor3 = item_selected_textcolor
end

local function update_explorer_ui(explorer: ExplorerUI)
	local node = explorer.node
	topbartitle.Text = node.parent and node.parent.instance.Name or node.instance.Name

	local cur_node: ExplorerNode? = explorer.node
	for _, item in ipairs(explorer.items) do
		if cur_node then
			item.show()
			item.update_to_node(cur_node)
			
			cur_node = get_next_node(cur_node)
		else
			item.hide()
		end
	end
end

local function expand_node(node: ExplorerNode, explorer: ExplorerUI)
	for _, child in ipairs(node.instance:GetChildren()) do
		local child_node = new_child_node(child, node)
		add_to_lookup(explorer.node_lookup, child_node)
	end
	node.expanded = true
end

local function create_explorer_item(explorer: ExplorerUI): ExplorerUIItem
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 20)
	frame.Parent = explorerframe

	local padding = add_padding(frame, 0, 0, 0, 0)
	local expand_icon_width = 30
	local class_icon_width = 16

	local instname = Instance.new("TextButton")
	instname.BorderSizePixel = 0
	instname.BackgroundTransparency = 1
	instname.AutoButtonColor = false
	instname.Size = UDim2.new(1, -20, 1, 0) 
	instname.Position = UDim2.fromOffset(expand_icon_width + class_icon_width + 5, 0)
	instname.TextXAlignment = Enum.TextXAlignment.Left
	instname.Parent = frame

	local expandframe = Instance.new("TextButton")
	expandframe.BackgroundTransparency = 1
	expandframe.TextTransparency = 1
	expandframe.Size = UDim2.new(0, expand_icon_width, 1, 0)
	expandframe.Parent = frame

	local expandicon = Instance.new("ImageLabel")
	expandicon.BackgroundTransparency = 1
	expandicon.Size = UDim2.fromOffset(5, 7)
	expandicon.Image = "http://www.roblox.com/asset/?id=7577501468"
	expandicon.ImageColor3 = Color3.fromRGB(63, 63, 63) -- this shouldn't have its own variable because this is just to darken another color
	expandicon.ImageTransparency = 0.5
	expandicon.Position = UDim2.fromScale(0.5, 0.5)
	expandicon.AnchorPoint = Vector2.new(0.5, 0.5)
	expandicon.Parent = expandframe

	local classicon = Instance.new("ImageLabel")
	classicon.BackgroundTransparency = 1
	classicon.Size = UDim2.fromOffset(class_icon_width, 16)
	classicon.Image = "rbxasset://textures/ClassImages.png"
	classicon.ImageRectSize = Vector2.new(16, 16)
	classicon.Position = UDim2.new(0, expand_icon_width, 0.5, 0)
	classicon.AnchorPoint = Vector2.new(0, 0.5)
	classicon.Parent = frame

	local item: ExplorerUIItem = {
		frame = frame,
		instname = instname,
		padding = padding,
		expandicon = expandicon,
		classicon = classicon
	}

	table.insert(connections,
		frame.MouseEnter:Connect(function()
			if item.node then
				color_hovered_item(item)
			end
		end)
	)

	table.insert(connections,
		frame.MouseLeave:Connect(function()
			if item.node then
				color_item(item)
			end
		end)
	)

	-- handle expand button
	table.insert(connections,
		expandframe.Activated:Connect(function()
			-- this might be confusing
			-- item.node isn't defined here
			-- it's defined somewhere else in the code (in 'update_explorer_ui')
			-- item.node actually refers to a ExplorerNode
			local node: ExplorerNode? = item.node
			if node then
				-- toggle expand
				node.expanded = not node.expanded
				if node.expanded then
					expand_node(item.node, explorer)
					--for _, child in ipairs(node.instance:GetChildren()) do
					--	local child_node = new_child_node(child, node)
					--	add_to_lookup(explorer.node_lookup, child_node)
					--end
				else
					contract_node(node)
				end

				-- this isn't handled here either
				-- a comment in ExplorerUI explains it
				explorer.should_update_ui = true
			end
		end)
	)
	
	function item.update_to_node(node: ExplorerNode)
		-- update references
		item.node = node
		node.last_item_associated = item

		-- update colors
		color_item(item)

		-- update indentation
		item.padding.PaddingLeft = UDim.new(0, node.indentation * 10)

		-- update expand icon
		item.expandicon.Rotation = node.expanded and 90 or 0

		-- update icon
		item.classicon.ImageRectOffset = icons_index[node.instance.ClassName] or default_icon_index

		-- update name
		local inst = node.instance
		item.instname.Text = inst.Name
		
		if item.update_name_event then
			item.update_name_event:Disconnect()
		end
		
		local connection = inst:GetPropertyChangedSignal("Name"):Connect(function()
			item.instname.Text = inst.Name
		end)
		
		item.update_name_event = connection
		connections[item] = item.update_name_event
	end
	
	function item.show()
		item.frame.Visible = true
	end
	
	function item.hide()
		item.frame.Visible = false
	end

	return item
end

local lookup: ExplorerNodeLookup = {}
setmetatable(lookup, {__mode = "v"})

local root_node = new_node(workspace)
add_to_lookup(lookup, root_node)

do
	local prev_node = root_node
	for _, servicename in ipairs(
		{"Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService"}
		)
	do
		local service = game:GetService(servicename)

		local node = new_node(service)
		node.back = prev_node
		prev_node.next = node
		add_to_lookup(lookup, node)

		prev_node = node
	end
end

local explorer: ExplorerUI = {
	node = root_node,
	items = {},
	node_lookup = lookup,
	should_update_ui = true
}

-- create explorer items
for i = 1, explorer_size / 20 do
	local item = create_explorer_item(explorer)
	table.insert(explorer.items, item)
end

-- update ui
table.insert(connections,
	game:GetService("RunService").Heartbeat:Connect(function()
		if explorer.should_update_ui then
			update_explorer_ui(explorer)
			explorer.should_update_ui = false
		end
	end)
)

-- handle when an instance is removed
table.insert(connections,
	game.DescendantRemoving:Connect(function(instance: Instance)
		local node: ExplorerNode? = explorer.node_lookup[instance]
		if node -- The instance is somewhere in the GUI
		then
			node.removed = true
			node.recently_added = false

			-- if changing .removed = true
			-- implies updating the screen
			-- then do it
			-- this checks if the node is visible in the screen
			if node.last_item_associated and node.last_item_associated.node == node then
				node.last_item_associated.update_to_node(node)
			end
		end
	end)
)

-- handle when an instance is added
table.insert(connections,
	game.DescendantAdded:Connect(function(instance: Instance)
		local parent_node: ExplorerNode? = instance.Parent and explorer.node_lookup[instance.Parent]
		if parent_node and parent_node.expanded then
			local node = new_child_node(instance, parent_node)
			add_to_lookup(explorer.node_lookup, node)
			node.recently_added = true

			-- if previous node is visible then it probably means this one will be too
			local prev_node = node.back or node.parent
			if prev_node and prev_node.last_item_associated and prev_node.last_item_associated.node == prev_node then
				prev_node.last_item_associated.update_to_node(node)
			end
		end
	end)
)

-- scrolling functionality
table.insert(connections,
	explorerframe.MouseWheelForward:Connect(function()
		local back = get_prev_node(explorer.node)
		if back then
			explorer.node = back
			explorer.should_update_ui = true
		end
	end)
)

table.insert(connections,
	explorerframe.MouseWheelBackward:Connect(function()
		local next = get_next_node(explorer.node)
		if next then
			explorer.node = next
			explorer.should_update_ui = true
		end
	end)
)

-- simple API
-- function _G.buslock_quit

-- this makes the explorer let you explore an instance
-- by doing _G.buslock_goto(instance)
function _G.buslock_goto(instance: Instance)
	local function get_node_of(instance: Instance)
		local node = explorer.node_lookup[instance]
		if node then
			return node 
		end

		assert(instance.Parent, "Instance cannot be parented to nil!")
		local parent_node = get_node_of(instance.Parent)
		expand_node(parent_node, explorer)
		return get_node_of(instance)
	end

	explorer.node = get_node_of(instance)
	explorer.should_update_ui = true
end