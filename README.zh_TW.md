# form.nvim

[English](README.md) | [繁體中文](README.zh_TW.md) | [版本變更紀錄](CHANGELOG.md)

`form.nvim` 是一個適用於 Neovim 0.12 以上版本、不需要第三方相依套件的輕量表單工具

透過原生 `vim.snippet` 提供表單欄位輸入與跳轉，支援單行及多行字串欄位。含有多行欄位的表單透過獨立 Extmark 追蹤欄位結構，編輯時提示結構錯誤，資料驗證與提交仍在執行 `:write` 時進行。不依賴 snippet 完成事件、私有 API、LSP 或外部套件

## 安裝

使用 Neovim 原生套件機制，在 macOS 或 Linux 的預設環境中執行：

```sh
mkdir -p ~/.local/share/nvim/site/pack/local/start
unzip form.nvim-unreleased.zip -d ~/.local/share/nvim/site/pack/local/start
```

如果已安裝舊版，請以新的 `form.nvim/` 目錄取代原本的 plugin 目錄，並重新啟動 Neovim

若有自訂資料目錄，可透過 `:echo stdpath('data')` 確認位置。執行 `:helptags ~/.local/share/nvim/site/pack/local/start/form.nvim/doc` 後，即可使用 `:help form.nvim` 查看說明

開發期間，也可以直接將本機專案目錄加入 `runtimepath`：

```lua
vim.opt.runtimepath:prepend('/path/to/form.nvim')
```

不需要呼叫 `setup()`，也不需要安裝其他套件管理器

## 快速開始

```lua
vim.api.nvim_create_user_command('LocationForm', function()
  require('form').open({
    title = 'location',
    fields = {
      { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
      { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
      { name = 'description', label = '描述', multiline = true, required = true },
    },
    format = 'json',
  })
end, {})
```

執行 `:LocationForm` 後，即可開始填寫表單

```text
經度: 121.5
緯度: 25.03
描述:
台北車站
  附近有許多商店
```

| 按鍵或指令 | 行為 |
| --- | --- |
| `Tab` | 跳到下一個 snippet 欄位 |
| `Shift-Tab` | 跳到上一個 snippet 欄位 |
| `Esc` | 離開輸入模式，不觸發資料驗證 |
| `:w ~/location.json` | 驗證全部欄位，成功後寫入指定檔案 |
| `]d` / `[d` | 跳到下一個或上一個 Diagnostic |

輸出範例（JSON 欄位順序不保證固定）：

```json
{"longitude":121.5,"latitude":25.03,"description":"台北車站\n  附近有許多商店"}
```

如果驗證失敗，Neovim 會顯示 Diagnostic，並阻止寫入。修正內容後再次執行 `:w` 即可，無須重新建立表單或重新進入 snippet

## API

`require('form').open(spec)` 會建立一個列在 buffer 清單中的 `acwrite` buffer，並回傳 buffer 編號。建議從 Normal mode、使用者自訂指令或 Normal mode 的映射呼叫

### 表單設定

| 屬性 | 說明 |
| --- | --- |
| `title` | 表單標題，預設為 `form` |
| `fields` | 欄位定義，必須是非空且有順序的陣列 |
| `window` | `split`（預設）、`vsplit` 或 `current` |
| `path` | 選填的預設輸出路徑，在開啟表單時轉成絕對路徑；`:w filename` 可覆蓋當次路徑 |
| `format` | `raw`（預設）、`json` 或自訂函數 `(data, ctx) -> string or string[]`，由內建寫入功能或 `ctx.serialize()`、`ctx.write()` 按需執行 |
| `validate` | 選填的整份表單驗證函數 `(data) -> nil or { field_name = 'message' }` |
| `on_submit` | 選填的同步提交函數 `(data, ctx)`，設定後自行控制提交，可選擇沿用內建寫入功能 |
| `mappings` | 是否設定 buffer-local 的 Tab 與 Shift-Tab 映射，預設為 `true` |
| `diagnostic` | 自訂 `vim.diagnostic` 顯示選項，與預設值合併 |
| `notify` | 是否顯示提交成功通知，預設為 `true` |

### 欄位設定

| 屬性 | 說明 |
| --- | --- |
| `name` | 唯一的資料鍵名，須以 ASCII 英文字母或 `_` 開頭，其餘可為英文字母、數字、`_`、`.`、`-`；`_form` 為保留名稱 |
| `label` | 顯示名稱，預設使用 `name`，可使用繁體中文，不可重複或包含冒號及控制字元 |
| `type` | 欄位型別：`string`（預設）、`number`、`integer`、`boolean` |
| `required` | 是否必填，預設為 `false`，設為 `true` 時不可留空或只輸入空白 |
| `multiline` | 是否允許多行內容，預設為 `false`，僅適用於 `string` 型別 |
| `default` | 單行純量預設值，或多行欄位可包含 LF、Tab 的字串；原生 snippet 會選取非空的預設值 |
| `min`、`max` | 數值型別的最小值與最大值，包含邊界值 |
| `validate` | 選填的欄位驗證函數 `(value) -> true` 或 `false, 'message'` |

### 資料型別與轉換

| 型別 | 轉換及驗證方式 |
| --- | --- |
| `string` | 字串 |
| `number` | 以 Lua `tonumber` 轉換，拒絕 NaN 及無限大 |
| `integer` | 數值必須為整數，不可包含小數部分 |
| `boolean` | 只能輸入 `true` 或 `false` |

單行欄位解析時會移除值前後的空白字元；多行欄位則保留非空白內容的原始換行、縮排及前後空白。若欄位留空或只包含空白字元，非必填欄位會省略（值為 `nil`），必填欄位則拒絕提交

只有成功轉換且非空的欄位才會執行自訂欄位驗證函數。所有欄位通過驗證後，才會執行整份表單的 `validate` 函數

### 多行欄位

在字串欄位設定 `multiline = true`，標籤會獨立佔用一行，值從下一行開始，其他欄位仍維持 `Label: value` 的原有格式

```lua
{
  name = 'description',
  label = '描述',
  type = 'string',
  multiline = true,
  default = [[第一行
  第二行

第三行]],
}
```

```text
標題: Hello
描述:
第一行
  第二行

第三行
作者: Admin
```

- 可使用 Enter 換行、貼上多行文字，或在多行欄位的內容區使用逐行編輯，不必強制縮排或輸入結束符號。即使清空內容，也須保留至少一行值所在的空白行
- 只要表單包含至少一個多行欄位，所有欄位都會使用獨立的 Extmark 標籤錨點，透過下一個錨點或 buffer 結尾計算值的範圍。即使內容中出現 `作者: Admin` 等類似欄位標籤的文字，也不會被誤判成其他欄位
- 欄位標籤文字、順序與行首位置必須保持完整；混合表單中的單行欄位也必須保留原本的標籤前綴，且不可跨行
- 不攔截 Normal mode 操作，也不會自動修改或修復文字。編輯時會重新檢查結構並顯示 Diagnostic（Insert mode 的顯示時機依 `diagnostic.update_in_insert`），可使用 `u` 與 `Ctrl-R` 復原或重做。整個標籤遭刪除或替換時，即使手動輸入相同文字也可能無法恢復錨點，建議使用 Undo。初始表單不列入 Undo 歷史，請避免整份替換混合表單的 buffer
- `vim.snippet` 仍負責原生 placeholder 與欄位跳轉。即使 session 結束，仍可繼續編輯及提交；結構檢查不會執行自訂驗證函數，直到 `:w` 才依序檢查結構、型別、資料及提交
- 未使用多行欄位的表單維持原本的逐行解析與寫入時驗證，也保留整行替換的使用方式

提交時收到的是 Lua 字串，而不是 table。JSON 格式會以 `\n` 編碼換行，raw 格式則保留原始 buffer 行內容

### 自訂驗證及跨欄位驗證

```lua
require('form').open({
  title = 'range',
  fields = {
    { name = 'start', type = 'integer', required = true },
    { name = 'finish', type = 'integer', required = true },
    {
      name = 'description', required = true,
      validate = function(value)
        return vim.fn.strchars(value) >= 3, '至少需要三個字元'
      end,
    },
  },
  validate = function(data)
    if data.finish < data.start then
      return { finish = '不得小於 start' }
    end
    -- nil 或 {} 代表通過驗證，可使用 _form 回傳整份表單的錯誤
  end,
  on_submit = function(data, ctx)
    vim.print(data, ctx)
  end,
})
```

## 寫入實體檔案

大部分表單不需要自行實作 `on_submit`，只要驗證通過、具備輸出路徑，且未設定自訂提交函數，便會使用內建寫入功能

| 指令 | 行為 |
| --- | --- |
| `:w` | 使用 `path` 設定的預設路徑；沒有路徑時只驗證及提交，不建立檔案 |
| `:w ~/my.txt` | 寫入本次指定的路徑 |
| `:w! ~/my.txt` | 允許取代已存在的一般檔案，但仍然必須通過驗證 |
| `:wq ~/my.txt` | 驗證及寫入成功後才關閉視窗 |
| `:w!` | 允許取代 `path` 指定的預設檔案 |

指定路徑只對當次寫入有效，表單仍會維持原本的 `form://` buffer 名稱。下一次單獨執行 `:w` 時不會沿用前一次指定的檔名。如果沒有設定 `path` 或 `on_submit`，會保留 v0.1.0 單純驗證的行為。若 Neovim 在觸發 `BufWriteCmd` 前就拒絕既有的指定檔案，則不會提交或寫入表單

### 輸出格式

| `format` | 輸出內容 |
| --- | --- |
| `raw` | 原始 buffer 內容，保留欄位標籤與原始空白，以 LF 分隔並在結尾加上換行 |
| `json` | 將驗證後的型別化資料編碼成 JSON 物件並加上換行，省略空白的非必填欄位，完全空白時輸出 `{}` |
| 自訂函數 | 回傳字串或連續的單行字串陣列，非空陣列以 LF 串接且結尾換行，空陣列輸出空檔案，字串若未以 LF 結尾則補上 LF |

輸出格式由 `format` 決定，而不是根據檔案副檔名自動判斷。內建寫入功能使用 UTF-8 與 LF，不套用 Neovim 的檔案編碼及換行格式選項

```lua
require('form').open({
  title = 'location',
  fields = {
    { name = 'longitude', type = 'number', required = true, min = -180, max = 180 },
    { name = 'latitude', type = 'number', required = true, min = -90, max = 90 },
    { name = 'description', required = true },
  },
  path = '~/location.txt', -- 選填，也可以透過 :w 指定路徑
  format = function(data, ctx)
    return {
      '經度：' .. data.longitude,
      '緯度：' .. data.latitude,
      '描述：' .. data.description,
    }
  end,
})
```

### 覆蓋保護與檔案權限

輸出路徑的上層目錄必須已經存在。內建寫入功能會先將完整內容寫入同目錄的暫存檔，再使用 hard link 建立新檔案，或使用 rename 取代 `:w!` 指定的既有一般檔案

新檔案會使用暫存檔的私有權限（POSIX 系統通常為 `0600`）；取代既有檔案時保留一般讀寫執行權限，但不保證保留所有者、ACL、延伸屬性或 hard link 的 inode 關係。檔案系統必須支援相應的 hard link 或 rename 操作

既有的 symbolic link、目錄或其他非一般檔案會被拒絕。這項功能不是備份工具或資安隔離機制

### 自訂提交行為

`on_submit(data, ctx)` 可用於特殊需求，例如呼叫 API、寫入資料庫或更新其他 buffer。設定後由 callback 自行控制提交，即使執行 `:w filename` 也不會自動格式化或寫入檔案；可透過 `ctx` 提供的方法沿用內建功能，也可以完全自行處理保存。Neovim 本身仍可能在呼叫 callback 前拒絕既有的指定檔案

| `ctx` 屬性 | 說明 |
| --- | --- |
| `bufnr` | 目前的表單 buffer 編號 |
| `title` | 表單標題 |
| `path` | 本次有效的絕對路徑，若未指定檔名也沒有設定預設路徑則為 `nil` |
| `force` | 布林值，代表此次指令是否包含 `!` |
| `serialize()` | 依照 `format` 回傳格式化後的字串，換行規則與內建寫入功能相同，不需要指定輸出路徑 |
| `write()` | 將格式化結果寫入本次有效路徑，沿用原本的覆蓋保護；成功回傳 `true`，失敗或沒有輸出路徑則拋出錯誤 |

例如，將 JSON 寫入檔案，並將完全相同的內容複製到系統剪貼簿：

```lua
format = 'json',
on_submit = function(data, ctx)
  local content = ctx.serialize()
  ctx.write()
  vim.fn.setreg('+', content)
end,
```

若只需要將自訂格式的內容複製到剪貼簿，不想建立檔案（即使有指定路徑）：

```lua
format = function(data, ctx)
  return data.description
end,
on_submit = function(data, ctx)
  vim.fn.setreg('+', ctx.serialize())
end,
```

兩個方法都不需要傳入參數，使用 `.` 呼叫即可

格式化採用延遲求值（lazy evaluation），第一次成功呼叫任一方法時才執行序列化，並快取結果（包含空字串）；同一次提交中重複呼叫會沿用該結果，每次新的提交則重新計算。若序列化失敗，不會快取錯誤

`ctx.write()` 使用本次提交已解析的路徑及 `!` 狀態，不受後續修改 `ctx.path` 或 `ctx.force` 的影響，並沿用內建的覆蓋保護與檔案寫入規則，不會自動建立父目錄。重複呼叫 `ctx.write()` 會各自執行寫入，因此未使用 `!` 時，第二次寫入可能失敗

這兩個方法僅在本次同步提交期間有效，不應保留至稍後執行，也不能從自訂 `format` 函數中遞迴呼叫。自訂格式函數會收到相同的 context 與已驗證的資料。未設定 `on_submit` 時，內建寫入也使用相同機制；若沒有輸出路徑，單獨執行 `:w` 仍只進行驗證。若只是一般檔案輸出，可直接省略 `on_submit`

回傳 `false, message` 或拋出 `error()` 代表提交失敗，其他正常回傳值（包含 `nil`）代表提交成功

`on_submit` 與自訂格式函數必須同步執行完畢，不應修改或刪除目前的表單 buffer。若 callback 已產生外部副作用後才失敗，plugin 無法代為復原

## 寫入行為與限制

- 當 Neovim 接受 `:w` 並進入表單寫入處理程序時，會重新驗證所有欄位，與 snippet 是否已結束或 buffer 是否已修改無關；重複提交會再次呼叫 callback
- 表單寫入處理程序中的驗證、序列化、檔案寫入或提交失敗時，會產生寫入錯誤、保留 `modified` 狀態並顯示 Diagnostic，`:w!` 也不能跳過驗證
- 寫入成功才會清除 Diagnostic 並將 `modified` 設為 `false`，失敗的 `:wq` 應保留表單視窗
- `:update` 與 `:x` 可能略過已經沒有修改的 buffer，這與 Neovim 原本的行為一致
- 資料驗證及提交錯誤的 Diagnostic 反映上次寫入結果；含有多行欄位的表單會另外隨文字變更更新結構 Diagnostic，下次寫入時重新檢查兩者
- 欄位順序與 schema 一致，單行欄位佔用一行，多行字串欄位使用獨立標籤行及一行以上的內容；標籤必須保持完整，值中可以包含冒號或與標籤相同的文字
- 不支援部分範圍寫入及追加寫入，也不支援以 `:saveas` 操作表單；建議使用 `:w filename`，而 `:write !command` 是 Neovim 的外部指令機制，不屬於表單提交
- 一般 buffer 不受影響；可以用 `:ls` 或 `:buffer` 找回隱藏表單，使用 `:bd!` 丟棄表單，`:q!` 則可能只關閉視窗而保留隱藏 buffer
- 全域選項 `autowrite`、`autowriteall` 也可能觸發寫入，若希望只在明確執行寫入時提交，請關閉這些選項

## 開發與測試

```sh
make test
# 或指定 Neovim 執行檔
make test NVIM=/path/to/nvim
```

Schema、序列化、提交 context 及模擬檔案系統的寫入單元測試，也可以使用獨立的 Lua 執行；整合測試需要 Neovim 0.12 以上版本，涵蓋寫入事件、驗證失敗重試、callback context 與延遲序列化、實體檔案、輸出格式、覆蓋保護、`:wq` 行為、多行範圍追蹤、結構 Diagnostic、Undo/Redo，以及 snippet 結束後的獨立提交

## 版本管理

請參考 [CHANGELOG.md](CHANGELOG.md)。本專案依循 [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) 及 [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)，尚未正式發布的變更一律記錄於 `Unreleased`，直到正式發布新版本才移入對應的版本區塊
