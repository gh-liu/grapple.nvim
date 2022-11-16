local log = require("grapple.log")
local scope = require("grapple.scope")
local state = require("grapple.state")
local types = require("grapple.types")

---@class Grapple.Tag
---@field file_path string
---@field cursor table

---@alias Grapple.TagKey string | integer
---@alias Grapple.TagTable table<Grapple.TagKey, Grapple.Tag>
---@alias Grapple.Cursor table

local M = {}

---@type table<string, Grapple.Tag[]>
local _tags = {}

---@private
---@param scope_ Grapple.Scope
local function _scoped_tags(scope_)
    local scope_path = scope.resolve(scope_)
    _tags[scope_path] = _tags[scope_path] or {}
    return _tags[scope_path]
end

---@private
---@param scope_ Grapple.Scope
---@param key Grapple.TagKey
---@return Grapple.Tag
local function _get(scope_, key)
    return _scoped_tags(scope_)[key]
end

---@private
---@param scope_ Grapple.Scope
---@param tag Grapple.Tag
---@param key Grapple.TagKey | nil
local function _set(scope_, tag, key)
    local scoped_tags = _scoped_tags(scope_)
    if key == nil then
        table.insert(scoped_tags, tag)
    elseif type(key) == "string" then
        scoped_tags[key] = tag
    elseif type(key) == "number" then
        table.insert(scoped_tags, key, tag)
    end
end

---@private
---@param scope_ Grapple.Scope
---@param tag Grapple.Tag
---@param key Grapple.TagKey
local function _update(scope_, tag, key)
    _scoped_tags(scope_)[key] = tag
end

---@private
---@param scope_ Grapple.Scope
---@param key Grapple.TagKey
local function _unset(scope_, key)
    local scoped_tags = _scoped_tags(scope_)
    if type(key) == "string" then
        scoped_tags[key] = nil
    elseif type(key) == "number" then
        table.remove(scoped_tags, key)
    end
end

---@private
local function _prune()
    for _, scope_path in ipairs(vim.tbl_keys(_tags)) do
        if vim.tbl_isempty(_tags[scope_path]) then
            _tags[scope_path] = nil
        end
    end
end

---@private
---@param scope_ Grapple.Scope
---@ereturn Grapple.TagTable
function M.tags(scope_)
    return vim.deepcopy(_scoped_tags(scope_))
end

---@param scope_ Grapple.Scope
function M.reset(scope_)
    local scope_path = scope.resolve(scope_)
    _tags[scope_path] = nil
end

---@param scope_ Grapple.Scope
---@param opts Grapple.Options
function M.tag(scope_, opts)
    local file_path
    local cursor

    if opts.file_path then
        if not state.file_exists(opts.file_path) then
            log.error("ArgumentError - file path does not exist. Path: " .. opts.file_path)
            error("ArgumentError - file path does not exist. Path: " .. opts.file_path)
        end
        file_path = opts.file_path
    elseif opts.buffer then
        if not vim.api.nvim_buf_is_valid(opts.buffer) then
            log.error("ArgumentError - buffer is invalid. Buffer: " .. opts.buffer)
            error("ArgumentError - buffer is invalid. Buffer: " .. opts.buffer)
        end
        file_path = vim.api.nvim_buf_get_name(opts.buffer)
        cursor = vim.api.nvim_buf_get_mark(opts.buffer, '"')
    else
        log.error("ArgumentError - a buffer or file path are required to tag a file.")
        error("ArgumentError - a buffer or file path are required to tag a file.")
    end

    ---@type Grapple.Tag
    local tag = {
        file_path = file_path,
        cursor = cursor,
    }

    local old_key = M.key(scope_, { file_path = file_path })
    if old_key ~= nil then
        log.warn(
            "Replacing tag. Old key: "
                .. old_key
                .. ". New key: "
                .. (opts.key or "[tbd]")
                .. ". Path: "
                .. tag.file_path
        )
        local old_tag = M.find(scope_, { key = old_key })
        tag.cursor = old_tag.cursor
        M.untag(scope_, { file_path = file_path })
    end

    _set(scope_, tag, opts.key)
end

---@param scope_ Grapple.Scope
---@param opts Grapple.Options
function M.untag(scope_, opts)
    local tag_key = M.key(scope_, opts)
    if tag_key ~= nil then
        _unset(scope_, tag_key)
    end
end

---@param scope_ Grapple.Scope
---@param tag Grapple.Tag
---@param cursor Grapple.Cursor
function M.update(scope_, tag, cursor)
    local tag_key = M.key(scope_, { file_path = tag.file_path })
    if tag_key ~= nil then
        local new_tag = vim.deepcopy(tag)
        new_tag.cursor = cursor
        _update(scope_, new_tag, tag_key)
    end
end

---@param tag Grapple.Tag
function M.select(tag)
    if tag.file_path == vim.api.nvim_buf_get_name(0) then
        log.debug("Tagged file is already the currently selected buffer.")
        return
    end

    if not state.file_exists(tag.file_path) then
        log.warn("Tagged file does not exist.")
        return
    end

    vim.api.nvim_cmd({ cmd = "edit", args = { tag.file_path } }, {})
    if tag.cursor then
        vim.api.nvim_win_set_cursor(0, tag.cursor)
    end
end

---@param scope_ Grapple.Scope
---@param opts Grapple.Options
---@return Grapple.Tag | nil
function M.find(scope_, opts)
    local tag_key = M.key(scope_, opts)
    if tag_key ~= nil then
        return _get(scope_, tag_key)
    else
        return nil
    end
end

---@param scope_ Grapple.Scope
---@param opts Grapple.Options
---@return Grapple.TagKey | nil
function M.key(scope_, opts)
    local tag_key = nil

    if opts.key then
        tag_key = opts.key
    elseif opts.file_path or (opts.buffer and vim.api.nvim_buf_is_valid(opts.buffer)) then
        local scoped_tags = M.tags(scope_)
        local buffer_name = opts.file_path or vim.api.nvim_buf_get_name(opts.buffer)
        for key, tag in pairs(scoped_tags) do
            if tag.file_path == buffer_name then
                tag_key = key
                break
            end
        end
    end

    return tag_key
end

---@param scope_ Grapple.Scope
---@return Grapple.TagKey[]
function M.keys(scope_)
    return vim.tbl_keys(_scoped_tags(scope_))
end

---@return string[]
function M.scopes()
    return vim.tbl_keys(_tags)
end

---@param scope_ Grapple.Scope
function M.reorder(scope_)
    local numbered_keys = vim.tbl_filter(function(key)
        return type(key) == "number"
    end, M.keys(scope_))
    table.sort(numbered_keys)

    local index = 1
    for _, key in ipairs(numbered_keys) do
        if key ~= index then
            M.tag(scope_, { file_path = _get(scope_, key).file_path, key = index })
        end
        index = index + 1
    end
end

---@param scope_ Grapple.Scope
---@param start_index integer
---@param direction Grapple.Direction
---@return Grapple.Tag | nil
function M.next(scope_, start_index, direction)
    local scoped_tags = M.tags(scope_)
    if #scoped_tags == 0 then
        return nil
    end

    local step = 1
    if direction == types.Direction.BACKWARD then
        step = -1
    end

    local index = start_index + step
    if index <= 0 then
        index = #scoped_tags
    end
    if index > #scoped_tags then
        index = 1
    end

    while scoped_tags[index] == nil and index ~= start_index do
        index = index + step
        if index <= 0 then
            index = #scoped_tags
        end
        if index > #scoped_tags then
            index = 1
        end
    end

    return scoped_tags[index]
end

---@param save_path string
function M.load(save_path)
    if state.file_exists(save_path) then
        _tags = state.load(save_path)
    end
end

---@param save_path string
function M.save(save_path)
    _prune()
    state.save(save_path, _tags)
end

---@private
---@param data table<string, Grapple.Tag[]>
function M._raw_load(data)
    _tags = data
end

---@private
---@return table<string, Grapple.Tag[]>
function M._raw_save()
    _prune()
    return _tags
end

return M