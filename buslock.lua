--!strict

-- Buslock explorer
-- I made it quickly (in 2 hours), so I didn't put much effort into refactoring it
-- It's complicated yet at the same time basic
-- It's quick, but at the same time it doesn't update the gui when a new child is added or an instance is destroyed

-- FEATURES:
-- - expand and contract
-- - explorer names do update
-- - when an instance is removed, the explorer instead of removing the button showing that instance, makes it become red
-- - able to drag the GUI
-- - proper disconnection of signals when the script is ran again or closed
-- - fast

-- Linked list implementation to store currently visible in the GUI game instances
type ExplorerNode = {
	instance: Instance,

	-- ui related
	indentation: number,
	removed: boolean, 	-- if the 'instance' property of this node was destroyed
	-- this is handled somewhere in the code via signals
	-- search ---HANDLING OF REMOVING--- to find that part

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

-- This just contains state about the current linked list
-- Only made in case I later want to have two explorer views
type ExplorerLinkedList = {
	instances_map: {[Instance]: ExplorerNode} -- NOTE: instance_node should always be a table with weak values
}

local function new_node(state: ExplorerLinkedList, instance: Instance): ExplorerNode
	local node: ExplorerNode = {
		instance = instance,
		indentation = 0,
		removed = false
	}
	
	state.instances_map[instance] = node
	return node
end

local function new_child_node(state: ExplorerLinkedList, instance: Instance, parent: ExplorerNode): ExplorerNode
	local node: ExplorerNode = {
		instance = instance,
		indentation = parent.indentation + 1,
		parent = parent,
		back = parent.last_child,
		removed = parent.removed
	}
	if parent.last_child then
		parent.last_child.next = node
	end
	if not parent.child then
		parent.child = node
	end
	parent.last_child = node
	
	state.instances_map[instance] = node	
	return node
end

local function expand_node(state: ExplorerLinkedList, node: ExplorerNode)
	-- TODO: this doesn't update when a new child is added or deleted
	for _, child in ipairs(node.instance:GetChildren()) do
		new_child_node(state, child, node)
	end
end

local function contract_node(node: ExplorerNode)
	node.child = nil
	node.last_child = nil
end

local function get_next_node(node: ExplorerNode): ExplorerNode?
	local ret = node.child or node.next
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
		while cur_node.last_child do
			cur_node = cur_node.last_child
		end
		
		return cur_node
	end
	
	if node.parent then
		return node.parent
	end

	return nil
end

local state: ExplorerLinkedList = {
	 instances_map = {}
}
setmetatable(state.instances_map, {__mode = "v"})

local root_node: ExplorerNode = new_node(state, workspace)

local ui_node: ExplorerNode = root_node

do
	local cur_node: ExplorerNode = root_node

	for _, servicename in ipairs(
		{"Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService"}
		)
	do
		local service = game:GetService(servicename)
		local node = new_node(state, service)
		node.back = cur_node

		cur_node.next = node

		assert(cur_node.next)
		cur_node = cur_node.next
	end
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

local sidebar_items_size = 20
local amount_of_items = 30

local topbar = Instance.new("Frame")
topbar.Size = UDim2.new(0, 200, 0, 20)
topbar.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
topbar.Parent = gui

local topbartitle = Instance.new("TextLabel")
topbartitle.TextXAlignment = Enum.TextXAlignment.Left
topbartitle.Size = UDim2.fromScale(1, 1)
topbartitle.BackgroundTransparency = 1
topbartitle.Parent = topbar

local titlepadding = Instance.new("UIPadding")
titlepadding.PaddingLeft = UDim.new(0, 5)
titlepadding.Parent = topbartitle

local closebutton = Instance.new("TextButton")
closebutton.Position = UDim2.fromScale(1, 0)
closebutton.AnchorPoint = Vector2.new(1, 0)
closebutton.Size = UDim2.fromScale(1, 1)
closebutton.SizeConstraint = Enum.SizeConstraint.RelativeYY
closebutton.Text = "X"
closebutton.Parent = topbar

local hidebutton = Instance.new("TextButton")
hidebutton.Position = UDim2.fromScale(0, 0)
hidebutton.AnchorPoint = Vector2.new(1, 0)
hidebutton.Size = UDim2.fromScale(1, 1)
hidebutton.SizeConstraint = Enum.SizeConstraint.RelativeYY
hidebutton.Text = "V"
hidebutton.Parent = closebutton

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(1, 0, 0, sidebar_items_size * amount_of_items)
sidebar.Position = UDim2.fromScale(0, 1)
sidebar.BorderSizePixel = 0
sidebar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sidebar.Parent = topbar

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = sidebar

hidebutton.Activated:Connect(function()
	sidebar.Visible = not sidebar.Visible
	hidebutton.Text = sidebar.Visible and "v" or "^"
end)

-- dragging
do
	local dragging = false
	local mouse = lp:GetMouse()

	table.insert(connections,
		topbar.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			local originX = mouse.X - topbar.AbsolutePosition.X
			local originY = mouse.Y - topbar.AbsolutePosition.Y

			dragging = true
			while dragging do
				topbar.Position = UDim2.fromOffset(mouse.X - originX, mouse.Y - originY)
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
type ExplorerUIItem = {
	frame: Frame,
	padding: UIPadding,
	instname: TextButton,
	expandicon: TextButton,
	node: ExplorerNode?,

	update_name_event: RBXScriptConnection?
}

local explorer_items: {ExplorerUIItem} = {}

local function get_item_background_color(item: ExplorerUIItem)
	return item.node and item.node.removed and Color3.fromRGB(250, 100, 60)
		or sidebar.BackgroundColor3
end

local function update_explorer_ui()
	local node: ExplorerNode? = ui_node
	topbartitle.Text = ui_node.parent and ui_node.parent.instance.Name or ui_node.instance.Name

	for _, item in ipairs(explorer_items) do
		if item.update_name_event then
			item.update_name_event:Disconnect()
			item.update_name_event = nil
			connections[item] = nil
		end

		if node then
			item.node = node	-- this is actually more involved
			-- due to the autonomous functioning of signals
			-- there is a lot more going on
			-- check out when the items are created
			-- that handles the expand button, and many other things
			-- this just instruments the expand button, which node to expand

			item.frame.Visible = true

			-- update background color
			item.frame.BackgroundColor3 = get_item_background_color(item)

			-- update indentation
			item.padding.PaddingLeft = UDim.new(0, node.indentation * 10)

			-- update expand icon
			item.expandicon.Text = node.child and "v" or ">"

			-- update name
			local inst = node.instance
			item.instname.Text = inst.Name
			item.update_name_event = inst:GetPropertyChangedSignal("Name"):Connect(function()
				item.instname.Text = inst.Name
			end)
			connections[item] = item.update_name_event

			node = get_next_node(node)
		else
			item.frame.Visible = false
		end
	end
end

-- create explorer items
for i = 1, amount_of_items do
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 20)
	frame.BackgroundTransparency = 0.5
	frame.Parent = sidebar

	local padding = Instance.new("UIPadding")
	padding.Parent = frame

	local instname = Instance.new("TextButton")
	instname.Name = "name"
	instname.BorderSizePixel = 0
	instname.BackgroundTransparency = 1
	instname.AutoButtonColor = false
	instname.Size = UDim2.new(1, -20, 1, 0) 
	instname.Position = UDim2.fromOffset(20, 0)
	instname.TextXAlignment = Enum.TextXAlignment.Left
	instname.Parent = frame

	local expandicon = Instance.new("TextButton")
	expandicon.Name = "expand"
	expandicon.BorderSizePixel = 0
	expandicon.BackgroundTransparency = 1
	expandicon.AutoButtonColor = false
	expandicon.Size = UDim2.new(0, 20, 1, 0)
	expandicon.Text = ">"
	expandicon.Parent = frame

	local item: ExplorerUIItem = {
		frame = frame,
		instname = instname,
		padding = padding,
		expandicon = expandicon
	}

	table.insert(connections,
		frame.MouseEnter:Connect(function()
			if item.node then
				frame.BackgroundColor3 =
					item.node.removed and Color3.fromRGB(250, 20, 20)
					or Color3.fromRGB(60, 100, 250)
			end
		end)
	)

	table.insert(connections,
		frame.MouseLeave:Connect(function()
			if item.node then
				frame.BackgroundColor3 = get_item_background_color(item)
			end
		end)
	)

	-- handle expand button
	table.insert(connections,
		expandicon.Activated:Connect(function()
			-- this might be confusing
			-- node.node isn't defined here
			-- it's defined somewhere else in the code (in 'update_explorer_ui')
			-- node.node actually refers to a ExplorerNode
			if item.node then
				-- toggle expand
				if not item.node.child then
					expand_node(state, item.node)
				else
					contract_node(item.node)
				end

				update_explorer_ui()
			end
		end)
	)

	table.insert(explorer_items, item)
end

update_explorer_ui()

-- scrolling functionality
table.insert(connections,
	sidebar.MouseWheelForward:Connect(function()
		local back = get_prev_node(ui_node)
		if back then
			ui_node = back
			update_explorer_ui()
		end
	end)
)

table.insert(connections,
	sidebar.MouseWheelBackward:Connect(function()
		local next = get_next_node(ui_node)
		if next then
			ui_node = next
			update_explorer_ui()
		end
	end)
)

---HANDLING OF REMOVING---
local update_ui = false

table.insert(connections,
	game.DescendantRemoving:Connect(function(inst)
		if state.instances_map[inst] then
			state.instances_map[inst].removed = true
			update_ui = true
		end
	end)
)

table.insert(connections,
	game:GetService("RunService").Heartbeat:Connect(function()
		-- this is so
		-- if many instances are removed in a frame
		-- it doesn't update multiple times in a frame but once
		if update_ui then
			update_explorer_ui()
			update_ui = false
		end
	end)
)

-- quit functionality
if _G.buslock_quit then
	_G.buslock_quit()
	_G.buslock_quit = nil
end

function _G.buslock_quit()
	gui:Destroy()

	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
end

closebutton.Activated:Connect(_G.buslock_quit)