local Model = require('lapis.db.model').Model
local Keystore = require'models.keystore'
local Account = require'models.account'
local StreamAccount = require'models.stream_account'
local SharedStream = require'models.shared_stream'
local format = string.format
local slugify = require('lapis.util').slugify
local pairs = pairs
local db = require'lapis.db'

local Stream = Model:extend('streams', {
  timestamp = true,
  relations = {
    {'user', belongs_to = 'User' },
    {'streams_accounts', has_many = 'StreamAccount' },
    {'stream_shares', has_many = 'SharedStream' },
  },
  check_user = function(self,user)
    if self.user_id == user.id then
      return true, true, true, nil
    end
    local ss = SharedStream:find({
      stream_id = self.id,
      user_id = user.id,
    })
    if ss then
      if ss.chat_level == 0 and ss.metadata_level == 0 then
        return false, 0, 0, 'Not authorized for this stream'
      end
      return true, ss.chat_level, ss.metadata_level, nil
    end
    return false, 0, 0, 'Not authorized for this stream'
  end,
  check_owner = function(self,user)
    if self.user_id ~= user.id then
      return false, 'User not authorized for this account'
    end
    return true, nil
  end,
  check_meta = function(self,user)
    if self:check_owner(user) then
      return 2 -- edit abilities
    end
    local ss = SharedStream:find({
      stream_id = self.id,
      user_id = user.id
    })
    if ss then
      return ss.metadata_level
    end
    return 0
  end,
  check_chat = function(self,user)
    if self:check_owner(user) then
      return 2 -- edit abilities
    end
    local ss = SharedStream:find({
      stream_id = self.id,
      user_id = user.id
    })
    if ss then
      return ss.chat_level
    end
    return 0
  end,
  get_stream_account = function(self,account)
    return StreamAccount:find({
      account_id = account.id,
      stream_id = self.id,
    })
  end,
  get_accounts = function(self)
    local accounts = {}
    local streams_accounts = self:get_streams_accounts()

    if streams_accounts then
      for i,v in pairs(streams_accounts) do
        local account = v:get_account()
        accounts[account.id] = account
      end
    end
    return accounts
  end,
  get_account = function(self, account)
    return self:get_accounts()[account.id]
  end,
  get_keystore = function(self)
    if not self.keystore then
      self.keystore = Keystore(nil,self.id)
    end
    return self.keystore
  end,
  set = function(self,key,value,exp)
    return self:get_keystore():set(key,value,exp)
  end,
  get = function(self,key)
    return self:get_keystore():get(key)
  end,
  get_all = function(self)
    return self:get_keystore():get_all()
  end,
  unset = function(self,key)
    return self:get_keystore():unset(key)
  end,
})

function Stream:create(parms)
  parms.uuid = uuid()
  return Model.create(self,parms)
end


function Stream:save_stream(user,stream,params)
  local stream = stream
  local slug = slugify(params.stream_name)
  local slug_stream = Stream:find({ user_id = user.id, slug = slug })
  params.preview_required = tonumber(params.preview_required)
  if not params.ffmpeg_pull_args or params.ffmpeg_pull_args:len() == 0 then
    params.ffmpeg_pull_args = db.NULL
  end
  if not stream then
    if slug_stream then
      return false, 'Stream name conflicts with ' .. slug_stream.name
    end
    stream = self:create({
      user_id = user.id,
      name = params.stream_name,
      slug = slug,
      preview_required = params.preview_required,
      ffmpeg_pull_args = params.ffmpeg_pull_args,
    })
  else
    if slug_stream and slug_stream.id ~= stream.id then
      return false, 'Stream name conflicts with ' .. slug_stream.name
    end
    stream:update({
      name = params.stream_name,
      slug = slug,
      preview_required = params.preview_required,
      ffmpeg_pull_args = params.ffmpeg_pull_args,
    })
  end

  for id, value in pairs(params.accounts) do
    local sa = StreamAccount:find({
      stream_id = stream.id,
      account_id = id,
    })

    if sa and value == false then
      sa:delete()
    elseif( (not sa) and value == true) then
      StreamAccount:create({
        stream_id = stream.id,
        account_id = id,
      })
    end
  end

  if not stream then
    return false, 'Failed to save stream'
  end

  return stream, nil
end

return Stream;

