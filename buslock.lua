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
	expanded: boolean,
	last_item_associated: ExplorerUIItem?, -- I put this here just to implement a clever trick to check if this node is currently visible in the GUI. useful to reduce some GUI updates. explained in `update_explorer_ui`
	removed: boolean, -- If the instance of this node was destroyed.
	-- This is implemented externally
	-- But in Buslock, I use a node_lookup and search for the comment ---HANDLE OF REMOVING---

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
	}
	
	return node
end

local function new_child_node(instance: Instance, parent: ExplorerNode): ExplorerNode
	local node: ExplorerNode = {
		instance = instance,
		indentation = parent.indentation + 1,
		expanded = false,
		removed = parent.removed,
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
	expandicon: TextButton,
	node: ExplorerNode?,

	update_name_event: RBXScriptConnection?
}

local function add_to_lookup(lookup: ExplorerNodeLookup, node: ExplorerNode)
	lookup[node.instance] = node
end

local function get_item_background_color(item: ExplorerUIItem)
	return item.node and item.node.removed and Color3.fromRGB(250, 100, 60)
		or sidebar.BackgroundColor3
end

local function get_item_hover_background_color(item: ExplorerUIItem)
	return item.node and item.node.removed and Color3.fromRGB(250, 20, 20)
		or Color3.fromRGB(60, 100, 250)
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
			
			-- update background color
			item.frame.BackgroundColor3 = get_item_background_color(item)

			-- update indentation
			item.padding.PaddingLeft = UDim.new(0, cur_node.indentation * 10)

			-- update expand icon
			item.expandicon.Text = cur_node.expanded and "v" or ">"

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
				frame.BackgroundColor3 = get_item_hover_background_color(item)
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
for i = 1, amount_of_items do
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
---HANDLE OF REMOVING---
table.insert(connections,
	game.DescendantRemoving:Connect(function(instance: Instance)
		local node: ExplorerNode? = explorer.node_lookup[instance]
		if node -- The instance is somewhere in the GUI
		then
			node.removed = true
			
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

-- scrolling functionality
table.insert(connections,
	sidebar.MouseWheelForward:Connect(function()
		local back = get_prev_node(explorer.node)
		if back then
			explorer.node = back
			explorer.should_update_ui = true
		end
	end)
)

table.insert(connections,
	sidebar.MouseWheelBackward:Connect(function()
		local next = get_next_node(explorer.node)
		if next then
			explorer.node = next
			explorer.should_update_ui = true
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