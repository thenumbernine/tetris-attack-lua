#!/usr/bin/env luajit
local sdl = require 'sdl'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local glreport = require 'gl.report'
local ThreadManager = require 'threadmanager'
local matrix = require 'matrix'
local table = require 'ext.table'

local App = require 'glapp.orbit'():subclass()
App.viewUseGLMatrixMode = true
App.title = 'Tetrid Attack'

local quad = matrix{
	{0,0},
	{1,0},
	{1,1},
	{0,1},
}

local function tex2D(...)
	local tex = GLTex2D(...)
		:setWrap{s=gl.GL_REPEAT, t=gl.GL_REPEAT}
		:setParameter(gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR)
		:setParameter(gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR)
		:unbind()
	return tex
end

function App:initGL()
	self.size = matrix{6,12}

	self.cursorTex = tex2D'cursor.png'

	self.texs = table{
		tex2D'diamond.png',
		tex2D'heart.png',
		tex2D'square.png',
		tex2D'star.png',
		tex2D'triangle.png',
	}

	self.board = self.size:zeros()
	for j=1,self.size[2]/2 do
		for i=1,self.size[1] do
			self.board[i][j] = math.random(#self.texs)
		end
	end

	self.view.ortho = true
	self.view.pos.x = self.size[1] / 2 + 1
	self.view.pos.y = self.size[2] / 2 + 1
	self.view.orthoSize = self.size[2] / 2

	self.pos = matrix{1,1}

	gl.glDisable(gl.GL_DEPTH_BUFFER_BIT)
	gl.glEnable(gl.GL_ALPHA_TEST)
	gl.glAlphaFunc(gl.GL_GREATER, .5)

	self.threads = ThreadManager()
	self:checkBoard()
end

App.switchFrame = 0
App.numSwitchFrames = 3

App.gameTime = 0
App.nextRaiseTime = 0
App.gameSpeed = 5		-- how long to raise a line

function App:update()
	App.super.update(self)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

	gl.glColor3f(1,1,1)
	GLTex2D:enable()

	local scrollOfs = (self.gameTime - self.nextRaiseTime) / self.gameSpeed

	for i in self.board:iter() do
		local b = self.board[i]
		local t = self.texs[b]
		if t then
			t:bind()
			gl.glBegin(gl.GL_QUADS)
			for _,ofs in ipairs(quad) do
				gl.glTexCoord2f(ofs[1], 1-ofs[2])
				gl.glVertex2f(i[1] + ofs[1], i[2] + ofs[2] + scrollOfs)
			end
			gl.glEnd()
			t:unbind()
		end
	end

	self.cursorTex:bind()
	gl.glBegin(gl.GL_QUADS)
	for _,ofs in ipairs(quad) do
		gl.glTexCoord2f(ofs[1], 1-ofs[2])
		gl.glVertex2f(
			self.pos[1] + ofs[1] * 2,
			self.pos[2] + ofs[2] + scrollOfs
		)
	end
	gl.glEnd()

	if self.switchFrame ~= 0 then
		local f = self.switchFrame / self.numSwitchFrames
		for side=0,1 do
			local x,y = self.switchPos:unpack()
			x = x + side
			local b = self.board[x][y]
			local t = self.texs[b]
			if t then
				t:bind()
				gl.glBegin(gl.GL_QUADS)
				for _,ofs in ipairs(quad) do
					gl.glTexCoord2f(ofs[1], 1-ofs[2])
					gl.glVertex2f(x+ofs[1]+(side==0 and 1 or -1)*f, y+ofs[2])
				end
				gl.glEnd()
				t:unbind()
			end
		end
	end

	self.cursorTex:unbind()

	GLTex2D:disable()

	local frameTime = 1/30
	local thisTime = os.clock()
	if not self.lastTime then
		self.lastTime = thisTime
	else
		local deltaTime = thisTime - self.lastTime
		if deltaTime > frameTime then
			while deltaTime >= frameTime do
				deltaTime = deltaTime - frameTime
				self.gameTime = self.gameTime + frameTime
				self.threads:update()
				self:checkInput()
			end
			self.lastTime = thisTime
		end
	end

	if self.gameTime >= self.nextRaiseTime then
		for y=self.size[2],1,-1 do
			for x=1,self.size[1] do
				if self.board[x][y] ~= 0 then
					if y == self.size[2] then error"YOU LOST" end
					self.board[x][y+1] = self.board[x][y]
				end
			end
		end
		for x=1,self.size[1] do
			self.board[x][1] = math.random(#self.texs)
		end
		self.pos[2] = self.pos[2] + 1
		self.nextRaiseTime = self.gameTime + self.gameSpeed
	end
end

function App:checkInput()
	if self.inputUp then
		self.pos[2] = math.min(self.pos[2] + 1, self.size[2])
	end
	if self.inputDown then
		self.pos[2] = math.max(self.pos[2] - 1, 1)
	end
	if self.inputLeft then
		self.pos[1] = math.max(self.pos[1] - 1, 1)
	end
	if self.inputRight then
		self.pos[1] = math.min(self.pos[1] + 1, self.size[1] - 1)
	end
	if self.inputSpace then
		if not self.switchPos then
			self.switchPos = matrix(self.pos)
			local x,y = self.pos:unpack()
			self.threads:add(function()
				-- animate or whatever
				for i=0,self.numSwitchFrames do
					self.switchFrame = i
					coroutine.yield()
				end
				self.board[x][y], self.board[x+1][y]
					= self.board[x+1][y], self.board[x][y]
				self.switchPos = nil
				self.switchFrame = 0

				self:checkDrop()
				self:checkBoard()
			end)
		end
	end
end

function App:event(event)
	if event[0].type == sdl.SDL_KEYDOWN
	or event[0].type == sdl.SDL_KEYUP
	then
		local down = event[0].type == sdl.SDL_KEYDOWN
		if event[0].key.keysym.sym == sdl.SDLK_UP then
			self.inputUp = down
		elseif event[0].key.keysym.sym == sdl.SDLK_DOWN then
			self.inputDown = down
		elseif event[0].key.keysym.sym == sdl.SDLK_LEFT then
			self.inputLeft = down
		elseif event[0].key.keysym.sym == sdl.SDLK_RIGHT then
			self.inputRight = down
		elseif event[0].key.keysym.sym == sdl.SDLK_SPACE then
			self.inputSpace = down
		end
	end
end

function App:checkBoard()
	self.doCheckBoard = true
	if self.checkBoardThread then return end

	self.checkBoardThread = self.threads:add(function()
		coroutine.yield()
		local hit

		repeat
			-- clear the flag.
			-- someone else will set it if we get another request
			self.doCheckBoard = nil

			for y=1,self.size[2] do
				for x=1,self.size[1] do
					local b = self.board[x][y]
					local xmin, xmax = x, x
					local ymin, ymax = y, y
					if b ~= 0 then
						while xmax <= self.size[1] and self.board[xmax][y] == b do xmax=xmax+1 end
						while xmin >= 1 and self.board[xmin][y] == b do xmin=xmin-1 end
						xmax = xmax - 1
						xmin = xmin + 1
						while ymax <= self.size[1] and self.board[x][ymax] == b do ymax=ymax+1 end
						while ymin >= 1 and self.board[x][ymin] == b do ymin=ymin-1 end
						ymax = ymax - 1
						ymin = ymin + 1
						if xmax-xmin+1>=3 then
							for k=xmin,xmax do
								hit = true
								self.board[k][y] = 0
							end
						end
						if ymax-ymin+1>=3 then
							for k=ymin,ymax do
								hit = true
								self.board[x][k] = 0
							end
						end
					end
				end
			end

			if hit then
				self:checkDrop()
			end
		until not self.doCheckBoard

		self.doCheckBoard = nil
		self.checkBoardThread = nil
	end)
end

function App:checkDrop()
	self.doCheckDrop = true
	if self.checkDropThread then return end

	self.checkDropThread = self.threads:add(function()
		coroutine.yield()
		repeat
			for i=1,5 do
				coroutine.yield()
			end
			self.doCheckDrop = nil
			local fall
			-- now drop pieces
			for y=2,self.size[2] do
				for x=1,self.size[1] do
					do local z=y --for z=y,2,-1 do
						if self.board[x][z] ~= 0
						and self.board[x][z-1] == 0
						then
							fall = true
							self.board[x][z-1] = self.board[x][z]
							self.board[x][z] = 0
						end
					end
				end
			end

			if fall then
				self:checkDrop()
				self:checkBoard()
			end
		until not self.doCheckDrop

		self.doCheckDrop = nil
		self.checkDropThread = nil
	end)
end

return App():run()
