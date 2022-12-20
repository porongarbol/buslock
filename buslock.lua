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
	node: ExplorerNode?,

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
		if item.update_name_event then
			item.update_name_event:Disconnect()
			item.update_name_event = nil
			connections[item] = nil
		end

		if cur_node then
			-- ok so this is complicated so I'll try to explain at the best of my ability

			-- the reason this is important is
			-- because buttons like 'expand' in the item
			-- need information about the node
			-- and this is the best way to give the node information to the item
			item.node = cur_node

			-- this is so I can check if a node is visible in the GUI
			-- we will start with a general assumption
			-- if cur_node.last_item_associated.node == item.node then node is visible
			-- why?
			-- let's say the first item stores a node
			-- if we scroll down, the first item will of course store another node
			-- however, the node that was in the first item, will still point to the first item
			-- while that first item stores information about other node
			cur_node.last_item_associated = item

			item.frame.Visible = true

			-- update colors
			color_item(item)

			-- update indentation
			item.padding.PaddingLeft = UDim.new(0, cur_node.indentation * 10)

			-- update expand icon
			item.expandicon.Rotation = cur_node.expanded and 90 or 0

			-- update name
			local inst = cur_node.instance
			item.instname.Text = inst.Name
			item.update_name_event = inst:GetPropertyChangedSignal("Name"):Connect(function()
				item.instname.Text = inst.Name
			end)
			connections[item] = item.update_name_event

			cur_node = get_next_node(cur_node)
		else
			item.frame.Visible = false
		end
	end
end

local function create_explorer_item(explorer: ExplorerUI)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 20)
	frame.Parent = explorerframe

	local padding = add_padding(frame, 0, 0, 0, 0)
	local expand_icon_width = 30

	local instname = Instance.new("TextButton")
	instname.BorderSizePixel = 0
	instname.BackgroundTransparency = 1
	instname.AutoButtonColor = false
	instname.Size = UDim2.new(1, -20, 1, 0) 
	instname.Position = UDim2.fromOffset(expand_icon_width, 0)
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

	local item: ExplorerUIItem = {
		frame = frame,
		instname = instname,
		padding = padding,
		expandicon = expandicon
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
					--expand_node(state, item.node)
					for _, child in ipairs(node.instance:GetChildren()) do
						local child_node = new_child_node(child, node)
						add_to_lookup(explorer.node_lookup, child_node)
					end
				else
					contract_node(node)
				end

				-- this isn't handled here either
				-- a comment in ExplorerUI explains it
				explorer.should_update_ui = true
			end
		end)
	)

	table.insert(explorer.items, item)
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
	create_explorer_item(explorer)
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
			-- the trick is explained in `update_explorer_ui`
			if node.last_item_associated and node.last_item_associated.node == node then
				explorer.should_update_ui = true
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
			-- this trick is explained in `update_explorer_ui`
			local prev_node = node.back or node.parent
			if prev_node and prev_node.last_item_associated and prev_node.last_item_associated.node == prev_node then
				explorer.should_update_ui = true
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