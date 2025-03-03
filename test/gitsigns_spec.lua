-- vim: foldnestmax=5:

local helpers = require('test.functional.helpers')(after_each)
local Screen = require('test.functional.ui.screen')

local clear         = helpers.clear
local command       = helpers.command
local exec_capture  = helpers.exec_capture
local feed          = helpers.feed
local exec_lua      = helpers.exec_lua
local eq            = helpers.eq
local matches       = helpers.matches
local sleep         = helpers.sleep
local split         = helpers.split
local get_buf_var   = helpers.curbufmeths.get_var
local fn            = helpers.funcs
local system        = fn.system

local function check_status(status)
  eq(status.head, get_buf_var('gitsigns_head'))
  eq(status, get_buf_var("gitsigns_status_dict"))
end

local scratch = os.getenv('PJ_ROOT')..'/scratch'
local gitdir = scratch..'/.git'
local test_file = scratch..'/dummy.txt'
local newfile = scratch.."/newfile.txt"

local test_file_text = {
  'This', 'is', 'a', 'file', 'used', 'for', 'testing', 'gitsigns.', 'The',
  'content', 'doesn\'t', 'matter,', 'it', 'just', 'needs', 'to', 'be', 'static.'
}

local function write_to_file(path, text)
  local f = io.open(path, 'wb')
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
end

local function git(args)
  system{"git", "-C", scratch, unpack(args)}
end

local function cleanup()
  system{"rm", "-rf", scratch}
end

local function setup_git()
  git{"init"}

  -- Always force color to test settings don't interfere with gitsigns systems
  -- commands (addresses #23)
  git{'config', 'color.branch'     , 'always'}
  git{'config', 'color.ui'         , 'always'}
  git{'config', 'color.diff'       , 'always'}
  git{'config', 'color.interactive', 'always'}
  git{'config', 'color.status'     , 'always'}
  git{'config', 'color.grep'       , 'always'}
  git{'config', 'color.pager'      , 'true'}
  git{'config', 'color.decorate'   , 'always'}
  git{'config', 'color.showbranch' , 'always'}

  git{'config', 'user.email', 'tester@com.com'}
  git{'config', 'user.name' , 'tester'}

  git{'config', 'init.defaultBranch', 'master'}
end

local function init(no_add)
  cleanup()
  system{"mkdir", scratch}
  setup_git()
  system{"touch", test_file}
  write_to_file(test_file, test_file_text)
  if not no_add then
    git{"add", test_file}
    git{"commit", "-m", "init commit"}
  end
end

local function command_fmt(str, ...)
  command(str:format(...))
end

local function edit(path)
  command_fmt("edit %s", path)
end

local function buf_var_exists(name)
  return pcall(get_buf_var, name)
end

local function match_lines(lines, spec)
  local i = 1
  for lid, line in ipairs(lines) do
    if line ~= '' then
      local s = spec[i]
      if s then
        if s.pattern then
          matches(s.text, line)
        else
          eq(s, line)
        end
      else
        local extra = {}
        for j=lid,#lines do
          table.insert(extra, lines[j])
        end
        error('Unexpected extra text:\n    '..table.concat(extra, '\n    '))
      end
      i = i + 1
    end
  end
  if i < #spec then
    error(('Did not match pattern \'%s\''):format(spec[i]))
  end
end

local function match_lines2(lines, spec)
  local i = 1
  for _, line in ipairs(lines) do
    if line ~= '' then
      local s = spec[i]
      if s then
        if s.pattern then
          if string.match(line, s.text) then
            i = i + 1
          end
        elseif s.next then
          eq(s.text, line)
          i = i + 1
        else
          if s == line then
            i = i + 1
          end
        end
      end
    end
  end

  if i < #spec + 1 then
    local unmatched = {}
    for j = i, #spec do
      table.insert(unmatched, spec[j].text or spec[j])
    end
    error(('Did not match patterns:\n    - %s'):format(table.concat(unmatched, '\n    - ')))
  end
end

local function debug_messages()
  return exec_lua("return require'gitsigns'.debug_messages(true)")
end

local function match_debug_messages(spec)
  match_lines(debug_messages(), spec)
end

local function match_dag(lines, spec)
  for _, s in ipairs(spec) do
    match_lines2(lines, {s})
  end
end

local function p(str)
  return {text=str, pattern=true}
end

local function n(str)
  return {text=str, next=true}
end

local test_config = {
  debug_mode = true,
  signs = {
    add          = {hl = 'DiffAdd'   , text = '+'},
    delete       = {hl = 'DiffDelete', text = '_'},
    change       = {hl = 'DiffChange', text = '~'},
    topdelete    = {hl = 'DiffDelete', text = '^'},
    changedelete = {hl = 'DiffChange', text = '%'},
  },
  keymaps = {
    noremap = true,
    buffer = true,
    ['n mhs'] = '<cmd>lua require"gitsigns.actions".stage_hunk()<CR>',
    ['n mhu'] = '<cmd>lua require"gitsigns.actions".undo_stage_hunk()<CR>',
    ['n mhr'] = '<cmd>lua require"gitsigns.actions".reset_hunk()<CR>',
    ['n mhp'] = '<cmd>lua require"gitsigns.actions".preview_hunk()<CR>',
    ['n mhS'] = '<cmd>lua require"gitsigns.actions".stage_buffer()<CR>',
    ['n mhU'] = '<cmd>lua require"gitsigns.actions".reset_buffer_index()<CR>',
  },
  update_debounce = 5,
}

describe('gitsigns', function()
  local screen
  local config

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach()

    screen:set_default_attr_ids({
      [1] = {foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray};
      [2] = {background = Screen.colors.LightMagenta};
      [3] = {background = Screen.colors.LightBlue};
      [4] = {background = Screen.colors.LightCyan1, bold = true, foreground = Screen.colors.Blue1};
      [5] = {foreground = Screen.colors.Brown};
      [6] = {foreground = Screen.colors.Blue1, bold = true};
      [7] = {bold = true},
      [8] = {foreground = Screen.colors.White, background = Screen.colors.Red};
      [9] = {foreground = Screen.colors.SeaGreen, bold = true};
    })

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
    exec_lua('gs = require("gitsigns")')
    config = helpers.deepcopy(test_config)
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)

  it('can run basic setup', function()
    screen:try_resize(60,6)
    exec_lua('gs.setup()')
    screen:expect{grid=[[
      ^                                                            |
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
                                                                  |
    ]]}
  end)

  it('index watcher works on a fresh repo', function()
    screen:try_resize(20,6)
    init(true)
    config.watch_index = {interval = 5}
    exec_lua('gs.setup(...)', config)
    edit(test_file)
    sleep(40)

    match_dag(debug_messages(), {
      "run_job: git --no-pager --version",
      'attach(1): Attaching',
      p'run_job: git .* config user.name',
      'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
      p('run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard '..test_file),
      'watch_index(1): Watching index',
      'watcher_cb(1): Index update error: ENOENT',
      p'run_job: git .* show :0:dummy.txt',
      'update(1): updates: 1, jobs: 5'
    })

    screen:expect{grid=[[
      {3:+ }^This              |
      {3:+ }is                |
      {3:+ }a                 |
      {3:+ }file              |
      {3:+ }used              |
                          |
    ]]}

    git{"add", test_file}
    sleep(20)

    screen:expect{grid=[[
      ^This                |
      is                  |
      a                   |
      file                |
      used                |
                          |
    ]]}
  end)

  it('can open files not in a git repo', function()
    screen:try_resize(60,6)
    exec_lua('gs.setup(...)', config)
    local tmpfile = os.tmpname()
    sleep(100)
    edit(tmpfile)
    sleep(100)
    screen:expect{grid=[[
      ^                                                            |
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
                                                                  |
    ]]}
    sleep(100)
    feed('iline<esc>')
    sleep(100)
    command("write")
    sleep(102)
    screen:expect{grid=([[
      lin^e                                                        |
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      "%s" 1L, 5C written                            |
    ]]):format(tmpfile)}
    match_debug_messages {
      "run_job: git --no-pager --version",
      'attach(1): Attaching',
      p"run_job: git .* config user.name",
      "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
      'attach(1): Not in git repo',
      'attach(1): Attaching',
      'run_job: git --no-pager config user.name',
      'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
      'attach(1): Not in git repo'
    }
  end)

  describe('when attaching', function()
    before_each(function()
      init()
      exec_lua('gs.setup(...)', config)
      sleep(10)
    end)

    it('can setup mappings', function()
      edit(test_file)
      sleep(20)

      local res = split(exec_capture('nmap <buffer>'), '\n')
      table.sort(res)

      -- Check all keymaps get set
      match_lines(res, {
        'n  mhS         *@<Cmd>lua require"gitsigns.actions".stage_buffer()<CR>',
        'n  mhU         *@<Cmd>lua require"gitsigns.actions".reset_buffer_index()<CR>',
        'n  mhp         *@<Cmd>lua require"gitsigns.actions".preview_hunk()<CR>',
        'n  mhr         *@<Cmd>lua require"gitsigns.actions".reset_hunk()<CR>',
        'n  mhs         *@<Cmd>lua require"gitsigns.actions".stage_hunk()<CR>',
        'n  mhu         *@<Cmd>lua require"gitsigns.actions".undo_stage_hunk()<CR>',
      })
    end)

    it('does not attach inside .git', function()
      edit(scratch..'/.git/index')
      sleep(20)

      match_debug_messages {
        "run_job: git --no-pager --version",
        'attach(1): Attaching',
        'attach(1): In git dir'
      }
    end)

    it('doesn\'t attach to ignored files', function()
      write_to_file(scratch..'/.gitignore', {'dummy_ignored.txt'})

      local ignored_file = scratch.."/dummy_ignored.txt"

      system{"touch", ignored_file}
      edit(ignored_file)
      sleep(20)

      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(1): Attaching",
        p"run_job: git .* config user.name",
        "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
        p"run_job: git .* ls%-files .*/dummy_ignored.txt",
        "attach(1): Cannot resolve file in repo",
      }

      check_status {head='master'}
    end)

    it('doesn\'t attach to non-existent files', function()
      edit(newfile)
      sleep(10)

      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(1): Attaching",
        p"run_job: git .* config user.name",
        "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
        p("run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard "..newfile),
        "attach(1): Not a file",
      }

      check_status {head='master'}

    end)

    it('doesn\'t attach to non-existent files with non-existent sub-dirs', function()
      edit(scratch..'/does/not/exist')

      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(1): Attaching",
        "attach(1): Not a path",
      }

      helpers.pcall_err(get_buf_var, 'gitsigns_head')
      helpers.pcall_err(get_buf_var, 'gitsigns_status_dict')

    end)

    it('can run copen', function()
      command("copen")
      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(2): Attaching",
        "attach(2): Non-normal buffer",
      }
    end)
  end)

  describe('highlights', function()
    it('get set up correctly', function()
      command("set termguicolors")

      config.signs.add.hl = nil
      config.signs.change.hl = nil
      config.signs.delete.hl = nil
      config.signs.changedelete.hl = nil
      config.signs.topdelete.hl = nil
      config.numhl = true
      config.linehl = true

      exec_lua('gs.setup(...)', config)
      sleep(10)

      match_dag(debug_messages(), {
        p'Deriving GitSignsChangeNr from GitSignsChange',
        p'Deriving GitSignsChangeLn from GitSignsChange',
        p'Deriving GitSignsDelete from DiffDelete',
        p'Deriving GitSignsDeleteNr from GitSignsDelete',
        p'Deriving GitSignsDeleteLn from GitSignsDelete',
        p'Deriving GitSignsAdd from DiffAdd',
        p'Deriving GitSignsAddNr from GitSignsAdd',
        p'Deriving GitSignsAddLn from GitSignsAdd',
        p'Deriving GitSignsDeleteNr from GitSignsDelete',
        p'Deriving GitSignsDeleteLn from GitSignsDelete',
        p'Deriving GitSignsChangeNr from GitSignsChange',
        p'Deriving GitSignsChangeLn from GitSignsChange'
      })

      eq('GitSignsChange xxx gui=reverse guibg=#ffbbff',
        exec_capture('hi GitSignsChange'))

      eq('GitSignsDelete xxx gui=reverse guifg=#0000ff guibg=#e0ffff',
        exec_capture('hi GitSignsDelete'))

      eq('GitSignsAdd    xxx gui=reverse guibg=#add8e6',
        exec_capture('hi GitSignsAdd'))
    end)

    it('update when colorscheme changes', function()
      command("set termguicolors")

      config.signs.add.hl = nil
      config.signs.change.hl = nil
      config.signs.delete.hl = nil
      config.signs.changedelete.hl = nil
      config.signs.topdelete.hl = nil
      config.linehl = true

      exec_lua('gs.setup(...)', config)
      sleep(10)

      eq('GitSignsChange xxx gui=reverse guibg=#ffbbff',
        exec_capture('hi GitSignsChange'))

      eq('GitSignsDelete xxx gui=reverse guifg=#0000ff guibg=#e0ffff',
        exec_capture('hi GitSignsDelete'))

      eq('GitSignsAdd    xxx gui=reverse guibg=#add8e6',
        exec_capture('hi GitSignsAdd'))

      eq('GitSignsAddLn  xxx gui=reverse guibg=#add8e6',
        exec_capture('hi GitSignsAddLn'))

      command('colorscheme blue')

      eq('GitSignsChange xxx gui=reverse guifg=#000000 guibg=#006400',
        exec_capture('hi GitSignsChange'))

      eq('GitSignsDelete xxx gui=reverse guifg=#000000 guibg=#ff7f50',
        exec_capture('hi GitSignsDelete'))

      eq('GitSignsAdd    xxx gui=reverse guifg=#000000 guibg=#6a5acd',
        exec_capture('hi GitSignsAdd'))

      eq('GitSignsAddLn  xxx gui=reverse guifg=#000000 guibg=#6a5acd',
        exec_capture('hi GitSignsAddLn'))
    end)
  end)

  describe('current line blame', function()
    it('doesn\'t error on untracked files', function()
      command("set updatetime=1")
      init(true)
      screen:detach()
      screen:attach({ext_messages=true})
      config.current_line_blame = true
      exec_lua('gs.setup(...)', config)
      sleep(20)
      edit(newfile)
      feed("iline<esc>")
      command("write")
      screen:expect{messages = { { content = { { "<" } }, kind = "" } } }
    end)
  end)

  describe('on_attach()', function()
    it('can prevent attaching to a buffer', function()
      init(true)
      exec_lua('config = ...', config)
      exec_lua[[config.on_attach = function()
        return false
      end
      ]]
      exec_lua('gs.setup(config)')
      edit(test_file)
      sleep(20)
      match_debug_messages {
        "run_job: git --no-pager --version",
        'attach(1): Attaching',
        p"run_job: git .* config user.name",
        "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
        p'run_job: git %-%-no%-pager %-%-git%-dir=.* %-%-stage %-%-others %-%-exclude%-standard .*',
        "attach(1): User on_attach() returned false"
      }
    end)
  end)

  describe('change_base()', function()
    it('works', function()
      screen:try_resize(20, 4)

      init()
      edit(test_file)

      feed('oEDIT<esc>')
      command('write')

      git{'add', test_file}
      git{"commit", "-m", "commit on main"}

      -- Don't setup gitsigns until the repo has two commits
      exec_lua('gs.setup(...)', config)

      screen:expect{
        grid=[[
          This                |
          EDI^T                |
          is                  |
          < 19L, 103C written |
        ]],
        condition = function()
          return fn.exists('#gitsigns') > 0
        end,
      }

      command('Gitsigns change_base ~')
      screen:expect[[
        {1:  }This              |
        {3:+ }EDI^T              |
        {1:  }is                |
        < 19L, 103C written |
      ]]
    end)
  end)

  local function testsuite(advanced_features)
    return function()
      before_each(function()
        config.use_decoration_api = advanced_features
        config.use_internal_diff = advanced_features
        init()
      end)

      it('apply basic signs', function()
        exec_lua('gs.setup(...)', config)
        edit(test_file)
        command("set signcolumn=yes")

        feed("dd") -- Top delete
        feed("j")
        feed("o<esc>") -- Add
        feed("2j")
        feed("x") -- Change
        feed("3j")
        feed("dd") -- Delete
        feed("j")
        feed("ddx") -- Change delete
        sleep(10)

        -- screen:snapshot_util()
        screen:expect{grid=[[
          {4:^ }is                |
          {1:  }a                 |
          {3:+ }                  |
          {1:  }file              |
          {2:~ }sed               |
          {1:  }for               |
          {4:_ }testing           |
          {1:  }The               |
          {2:% }^oesn't            |
          {1:  }matter,           |
          {1:  }it                |
          {1:  }just              |
          {1:  }needs             |
          {1:  }to                |
          {1:  }be                |
          {1:  }static.           |
                              |
        ]]}

      end)

      it('perform actions', function()
        screen:try_resize(20,6)
        exec_lua('gs.setup(...)', config)
        edit(test_file)
        command("set signcolumn=yes")

        feed("jjj")
        feed("cc")
        sleep(20)
        feed("EDIT<esc>")
        sleep(10)

        screen:expect{grid=[[
          {1:  }This              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDI^T              |
          {1:  }used              |
                              |
        ]]}

        -- Stage
        feed("mhs")
        sleep(10)

        screen:expect{grid=[[
          {1:  }This              |
          {1:  }is                |
          {1:  }a                 |
          {1:  }EDI^T              |
          {1:  }used              |
                              |
        ]]}

        -- Undo stage
        feed("mhu")
        sleep(10)

        screen:expect{grid=[[
          {1:  }This              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDI^T              |
          {1:  }used              |
                              |
        ]]}

        -- Add multiple edits
        feed('gg')
        sleep(20)
        feed('cc')
        sleep(20)
        feed('That<esc>')
        sleep(10)

        screen:expect{grid=[[
          {2:~ }Tha^t              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDIT              |
          {1:  }used              |
                              |
        ]]}

        -- Stage buffer
        feed("mhS")
        sleep(10)

        screen:expect{grid=[[
          {1:  }Tha^t              |
          {1:  }is                |
          {1:  }a                 |
          {1:  }EDIT              |
          {1:  }used              |
                              |
        ]]}

        -- Unstage buffer
        feed("mhU")
        sleep(10)

        screen:expect{grid=[[
          {2:~ }Tha^t              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDIT              |
          {1:  }used              |
                              |
        ]]}

        -- Reset
        feed("mhr")
        sleep(10)

        screen:expect{grid=[[
          {1:  }Thi^s              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDIT              |
          {1:  }used              |
                              |
        ]]}

      end)

      it('can enable numhl', function()
        config.numhl = true
        exec_lua('gs.setup(...)', config)
        edit(test_file)
        command("set signcolumn=no")
        command("set number")

        feed("dd") -- Top delete
        feed("j")
        feed("o<esc>") -- Add
        feed("2j")
        feed("x") -- Change
        feed("3j")
        feed("dd") -- Delete
        feed("j")
        sleep(40)
        feed("ddx") -- Change delete
        sleep(100)

        -- screen:snapshot_util()
        screen:expect{grid=[[
          {4:  1 }is              |
          {5:  2 }a               |
          {3:  3 }                |
          {5:  4 }file            |
          {2:  5 }sed             |
          {5:  6 }for             |
          {4:  7 }testing         |
          {5:  8 }The             |
          {2:  9 }^oesn't          |
          {5: 10 }matter,         |
          {5: 11 }it              |
          {5: 12 }just            |
          {5: 13 }needs           |
          {5: 14 }to              |
          {5: 15 }be              |
          {5: 16 }static.         |
                              |
        ]]}
      end)

      it('attaches to newly created files', function()
        screen:try_resize(4, 4)
        exec_lua('gs.setup(...)', config)
        edit(newfile)
        sleep(100)
        exec_lua('gs.clear_debug()')
        command("write")
        sleep(40)

        local messages = {
          "attach(1): Attaching",
          p"run_job: git .* config user.name",
          "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
          p"run_job: git .* ls%-files .*",
          "watch_index(1): Watching index",
          p"run_job: git .* show :0:newfile.txt"
        }

        if not advanced_features then
          table.insert(messages, p'run_job: git .* diff .* /tmp/lua_.* /tmp/lua_.*')
        end

        local jobs = advanced_features and 8 or 9
        table.insert(messages, "update(1): updates: 1, jobs: "..jobs)

        match_debug_messages(messages)

        check_status {head='master', added=1, changed=0, removed=0}

        screen:expect{grid=([[
          {3:+ }^          |
          {6:~           }|
          {6:~           }|
          <0C written |
        ]]):format(jobs)}

      end)

      it('can add untracked files to the index', function()
        screen:try_resize(10, 4)
        exec_lua('gs.setup(...)', config)

        edit(newfile)
        feed("iline<esc>")
        command("write")
        sleep(20)

        -- screen:snapshot_util()
        screen:expect{grid=[[
          {3:+ }lin^e      |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

        feed('mhs') -- Stage the file (add file to index)
        sleep(20)

        screen:expect{grid=[[
          lin^e        |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

      end)

      it('tracks files in new repos', function()
        screen:try_resize(10, 4)
        exec_lua('gs.setup(...)', config)
        system{"touch", newfile}
        edit(newfile)

        feed("iEDIT<esc>")
        command("write")

        screen:expect{grid=[[
          {3:+ }EDI^T      |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

        -- Stage
        git{"add", newfile}

        screen:expect{grid=[[
          EDI^T        |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

        -- Reset
        git{"reset"}

        screen:expect{grid=[[
          {3:+ }EDI^T      |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

      end)

      it('can detach from buffers', function()
        exec_lua('gs.setup(...)', config)
        edit(test_file)
        command("set signcolumn=yes")

        feed("dd") -- Top delete
        feed("j")
        feed("o<esc>") -- Add
        feed("2j")
        feed("x") -- Change
        feed("3j")
        feed("dd") -- Delete
        feed("j")
        feed("ddx") -- Change delete
        sleep(10)

        screen:expect{grid=[[
          {4:^ }is                |
          {1:  }a                 |
          {3:+ }                  |
          {1:  }file              |
          {2:~ }sed               |
          {1:  }for               |
          {4:_ }testing           |
          {1:  }The               |
          {2:% }^oesn't            |
          {1:  }matter,           |
          {1:  }it                |
          {1:  }just              |
          {1:  }needs             |
          {1:  }to                |
          {1:  }be                |
          {1:  }static.           |
                              |
        ]]}

        exec_lua('gs.detach()')

        screen:expect{grid=[[
          {1:  }is                |
          {1:  }a                 |
          {1:  }                  |
          {1:  }file              |
          {1:  }sed               |
          {1:  }for               |
          {1:  }testing           |
          {1:  }The               |
          {1:  }^oesn't            |
          {1:  }matter,           |
          {1:  }it                |
          {1:  }just              |
          {1:  }needs             |
          {1:  }to                |
          {1:  }be                |
          {1:  }static.           |
                              |
        ]]}

        assert(not buf_var_exists('gitsigns_head'),
          'gitsigns_status_dict should not be defined')

        assert(not buf_var_exists('gitsigns_status_dict'),
          'gitsigns_head should not be defined')

        assert(not buf_var_exists('gitsigns_status'),
          'gitsigns_status should not be defined')
      end)

      it('can stages file with merge conflicts', function()
        screen:try_resize(40, 8)
        exec_lua('gs.setup(...)', config)
        command("set signcolumn=yes")

        -- Edit a file and commit it on main branch
        edit(test_file)
        feed('iedit')
        sleep(20)
        command("write")
        sleep(20)
        command("bdelete")
        sleep(20)
        git{'add', test_file}
        git{"commit", "-m", "commit on main"}

        -- Create a branch, remove last commit, edit file again
        git{'checkout', '-B', 'abranch'}
        git{'reset', '--hard', 'HEAD~1'}
        edit(test_file)
        feed('idiff')
        sleep(20)
        command("write")
        command("bdelete")
        git{'add', test_file}
        git{"commit", "-m", "commit on branch"}
        sleep(20)

        git{"rebase", "master"}
        sleep(20)

        -- test_file should have a conflict
        edit(test_file)
        sleep(50)
        screen:expect{grid=[[
          {2:~ }^<<<<<<< HEAD                          |
          {3:+ }editThis                              |
          {3:+ }=======                               |
          {3:+ }idiffThis                             |
          {3:+ }>>>>>>> {MATCH:.......} (commit on branch)    |
          {1:  }is                                    |
          {1:  }a                                     |
          {7:-- INSERT --}                            |
        ]]}

        exec_lua('require("gitsigns.actions").stage_hunk()')

        screen:expect{grid=[[
          {1:  }^<<<<<<< HEAD                          |
          {1:  }editThis                              |
          {1:  }=======                               |
          {1:  }idiffThis                             |
          {1:  }>>>>>>> {MATCH:.......} (commit on branch)    |
          {1:  }is                                    |
          {1:  }a                                     |
          {7:-- INSERT --}                            |
        ]]}

      end)

      it('handle files with spaces', function()
        screen:try_resize(20,6)
        exec_lua('gs.setup(...)', config)
        command("set signcolumn=yes")

        local spacefile = scratch..'/a b c d'

        write_to_file(spacefile, {'spaces', 'in', 'file'})

        edit(spacefile)

        screen:expect{grid=[[
          {3:+ }^spaces            |
          {3:+ }in                |
          {3:+ }file              |
          {6:~                   }|
          {6:~                   }|
                              |
        ]]}

        git{'add', spacefile}
        sleep(100)
        edit(spacefile)

        screen:expect{grid=[[
          {1:  }^spaces            |
          {1:  }in                |
          {1:  }file              |
          {6:~                   }|
          {6:~                   }|
                              |
        ]]}

      end)
    end
  end

  -- Run regular config
  describe('diff-ext', testsuite(false))

  -- Run with:
  --   - internal diff (ffi)
  --   - decoration provider
  describe('diff-int', testsuite(true))

  -- TODO Add test for current_line_blame
  -- TODO Add test for toggle_current_line_blame

  -- TODO Add test for #163: signcolumn=number with signs disabled shouldn't
  -- overwrite number column

  -- TODO Test config.attach_to_untracked
  -- TODO Add test for #194: Should not attach if file is in a custom git dir

  -- TODO Add test diffthis

end)
