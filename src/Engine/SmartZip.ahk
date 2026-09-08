;@Ahk2Exe-SetName         SmartZip
;@Ahk2Exe-SetDescription  7-zip的功能扩展
;@Ahk2Exe-SetCopyright    Copyright (c) since 2022
;@Ahk2Exe-SetCompanyName  viv
;@Ahk2Exe-SetOrigFilename SmartZip.exe
;@Ahk2Exe-SetMainIcon     ico.ico
;@Ahk2Exe-SetFileVersion 3.4
;@Ahk2Exe-SetProductVersion 17
;@Ahk2Exe-ExeName SmartZip.exe
buildVersion := 18
MainVersion := "3.4"
;Msgbox FormatTime(A_Now, "yyyy/M/d H:m:s")
buileTime := "2022/8/3 14:27:28"
app := "SmartZip"
#SingleInstance off
#NoTrayIcon
#Requires AutoHotkey v2.0
; SmartZip Modern adaptation; see ThirdPartyNotices.md for changes.
if EnvGet("SMARTZIP_MODERN_TEST") = "1"
    OnError(ReportTestError)
ReportTestError(err, mode) {
    FileAppend("ERROR line " err.Line ": " err.Message "`n" err.Stack "`n", "*", "UTF-8")
    ExitApp(3)
}

dataDir := EnvGet("SMARTZIP_MODERN_DATA")
if !dataDir
    dataDir := EnvGet("LOCALAPPDATA") "\SmartZip Modern\UserData"
DirCreate(dataDir)
ini.Init(dataDir "\SmartZip.ini")
IniCreate
zip := SmartZip(RelativePath(ini.zipDir))

;https://www.iconfont.cn/collections/detail?spm=a313x.7781069.0.da5a778a4&cid=24599
icon := FileExist(icon := RelativePath(ini.icon)) ? icon : ""

if icon
    TraySetIcon(icon)

if A_Args.Length
    zip.Init(A_Args).Exec()
else
    Setting

class SmartZip
{
    __New(sevenZipDir)
    {
        this.now := A_TickCount
        this.exitCode := -1
        this.setShow := false

        sevenZipDir := sevenZipDir ~= "i)^[a-z]:\\$" ? sevenZipDir : RTrim(sevenZipDir, "\")

        if !DirExist(sevenZipDir)
            return MsgBox("7-zip 文件夹不存在,请设置其路径")

        this.7z := sevenZipDir "\7z.exe"
        this.7zG := sevenZipDir "\7zG.exe"
        this.7zFM := sevenZipDir "\7zFM.exe"

        if !FileExist(this.7z) || !FileExist(this.7zG) || !FileExist(this.7zFM)
            return MsgBox("7-zip 文件夹中必需包含 7z.exe,7zG.exe,7zFM.exe`n请检测文件夹是否设置正确")
        this.7z := '"' this.7z '"'
        this.7zG := '"' this.7zG '"'
        this.7zFM := '"' this.7zFM '"'
    }

    Init(argsArr)
    {
        this.codePage := ""
        if argsArr[1] = "xc"
            SetCodePage(), argsArr.RemoveAt(1)

        if RegExMatch(argsArr[1], "^[xoa]$")
            this.to := argsArr[1], argsArr.RemoveAt(1)	;根据第一个传入参数决定动作
        else
            this.to := "x"

        this.arr := []
        for i in argsArr
        {
            if FileExist(i)
                loop files RTrim(i, "\"), "DF"
                    this.arr.Push(A_LoopFileFullPath)
        }

        if !this.arr.Length
            ExitApp(2)
        this.isRunning := true
        this.muilt := this.arr.Length > 1	;多文件

        SplitPath(this.arr[1], , &dir)
        SetWorkingDir(this.defaultDir := dir)

        this.continue := this.guiShow := this.cmdHide := false
        this.pid := this.log := this.testLog := ''

        this.ext := Map()
        this.extExp := []

        ini.ReadLoop("ext", this.ext, true)
        ini.ReadLoop("extExp", this.extExp)

        this.logLevel := ini.logLevel

        this.cmdLog := ini.cmdLog
        this.hideRunSize := ini.hideRunSize

        if this.logLevel || this.cmdLog
            OnExit(ExitLog)

        return this

        ExitLog(*)
        {
            if this.log
                FileAppend(this.log "`n", A_ScriptDir "\log.txt", "UTF-8")
            if this.testLog
                FileAppend(this.testLog "`n", A_ScriptDir "\cmdLog.txt", "UTF-8")
        }

        SetCodePage()
        {
            ini.ReadLoop("codepage", cpCustomArr := [])
            arr := ["简体中文（GBK）", "繁体中文（大五码）", "日文（Shift_JIS）", "韩文（EUC-KR）", "UTF-8 Unicode"]
            for i in cpCustomArr
                arr.Push(i)
            cpArr2 := [936, 950, 932, 949, 65001]

            cpG := gui("+AlwaysOnTop +ToolWindow", "请选择或输入你需要的代码页")
            cpG.AddText()
            cpG.SetFont(, "Segoe UI")
            cpG.AddLink("", '<a href="https://docs.microsoft.com/zh-cn/windows/win32/intl/code-page-identifiers">其他代码页</a>')
            v := cpG.AddComboBox("", arr)
            v.ToolTip := "如需添加其他常用代码页,请参考上方链接`n输入 数字(标识符) 点击右边的 添加`n删除只能移除添加的项目"
            cpG.AddButton("yp", "添加").OnEvent("Click", Add)
            cpG.AddButton("yp", "删除").OnEvent("Click", Delete)
            cpG.AddText()
            cpG.AddButton("", "确定").OnEvent("Click", DetectCp)
            cpG.OnEvent("Escape", Close)
            cpG.OnEvent("Close", Close)
            cpG.Show()
            OnMessage(0x200, WM_MOUSEMOVE)
            WinWaitClose(cpg.Hwnd)

            Close(*) => (OnMessage(0x200, WM_MOUSEMOVE, 0), cpg.Destroy())

            Add(*)
            {
                if !(text := v.Text) || !IsNumber(text)
                    return
                for i in arr
                    if i = text
                        return
                cpCustomArr.Push(text), arr.push(Text), v.Delete(), v.Add(arr)
            }

            Delete(*)
            {
                if v.Value < 6 || !(text := v.Text) || !IsNumber(text)
                    return
                cpCustomArr.RemoveAt(v.Value - 5), arr.RemoveAt(v.Value), arr.Text := "", v.Delete(), v.Add(arr)

            }

            DetectCp(*)
            {
                if IsNumber(text := v.Text)
                    this.codePage := " -mcp=" text
                else
                {
                    for i in arr
                    {
                        if text = i
                        {
                            this.codePage := " -mcp=" cpArr2[A_Index]
                            break
                        }
                    }
                }

                for i in cpCustomArr
                {
                    if ini.Read(A_Index, , "codepage") != i
                        ini.Write(i, A_Index, "codepage")
                }
                loop
                {
                    if !(vaf := ini.Read(cpCustomArr.Length + A_Index, , "codepage"))
                        break
                    ini.Delete("codepage", cpCustomArr.Length + A_Index)
                }

                Close
            }

        }
    }

    Exec()
    {
        switch this.to
        {
            case "x": this.Unzip()
            case "o": this.OpenZip()
            case "a": this.CreateZip()
            default:this.Unzip()
        }
        this.isRunning := false
        if this.cmdHide && !this.guiShow
        {
            ToolTip("处理完成")
            Sleep(2000)
            ToolTip()
        }
        if !this.setShow
            ExitApp
    }

    Unzip(loopPath := "")
    {
        if !loopPath
        {
            arr := this.arr
            this.autoAddPass := ini.autoAddPass
            this.dynamicPassSort := ini.dynamicPassSort
            this.test := ini.test
            this.partSkip := ini.partSkip
            this.delSource := ini.delSource
            this.delWhenHasPass := ini.delWhenHasPass
            this.nesting := ini.nesting
            this.nestingMuilt := ini.nestingMuilt
            this.succesSpercent := ini.successPercent
            this.autoRemovePass := ini.autoRemovePass
            if (targetDir := ini.targetDir)
                targetDir := targetDir ~= "i)^[a-z]:\\$" ? targetDir : RTrim(targetDir, "\")

            this.addDir2Pass := ini.Read("addDir2Pass", , "set")

            if targetDir && DirExist(targetDir)
                SetWorkingDir(this.defaultDir := targetDir)

            this.password := ["", ini.lastPass, FormatPassword(A_Clipboard)]

            ini.ReadLoop("password", this.password)

            excludeExt := []
            ini.ReadLoop("excludeExt", excludeExt)
            excludeName := []
            ini.ReadLoop("excludeName", excludeName)
            this.excludeArgs := ""
            if excludeExt.Length || excludeName.Length
            {
                for i in excludeExt
                    this.excludeArgs .= ' -x!*.' i
                for i in excludeName
                    this.excludeArgs .= ' -x!*' i '*'
            }
            if this.excludeArgs
                this.excludeArgs .= " -r"

            if this.dynamicPassSort || this.autoAddPass
            {
                ini.ReadLoop("password", this.dynamicPassArr := [])
                this.passwordMap := Map()

                for i in this.dynamicPassArr
                {
                    this.passwordMap[i] := A_Index
                    this.dynamicPassArr[A_Index] := [i, ini.Read(A_Index, 0, "passwordSort")]
                    ; if !IsNumber(this.dynamicPassArr[A_Index][2])
                    ; ini.Write(this.dynamicPassArr[A_Index][2] := 0, A_Index, "passwordSort")
                }
            }

            this.fileSystemObject := ComObject("Scripting.FileSystemObject")

        } else
        {
            arr := [loopPath]
            SplitPath(loopPath, , &dir)
            SetWorkingDir(dir)
        }

        for i in arr
        {
            if !loopPath && A_WorkingDir != this.defaultDir
                SetWorkingDir(this.defaultDir)
            if !loopPath
                this.index := A_Index

            this.temp := tmpDir := '__7z' A_Now '_' DllCall("GetCurrentProcessId") '_' A_TickCount

            this.currentSize := FileGetSize(i)
            hideBool := this.currentSize / 1024 / 1024 < this.hideRunSize

            part := IsPart(i)
            if this.partSkip && !part
                continue

            if this.muilt && !this.guiShow && !hideBool
                this.Gui()

            if this.addDir2Pass
                SplitPath(i, , &dir), this.password.Push(RegExReplace(dir, ".+\\"))
            zipx(i)
            if this.addDir2Pass
                this.password.RemoveAt(this.password.Length)

            if !DirExist(tmpDir)	;密码错误以及未输入正确密码
                continue

            loop files tmpDir "\*.*", "RDF"
                AfterUnzip(A_LoopFileFullPath)

            loop files tmpDir "\*.*", "DF"
            {
                count := A_Index, souceFile := A_LoopFileFullPath
                if A_Index > 2
                    break
            }

            ;解压后没有文件
            if !IsSet(count)
            {
                this.RecycleItem(tmpDir, A_LineNumber, true)
                continue
            }

            notDir := 0
            loop files tmpDir "\*.*", "FR"
            {
                if !DirExist(A_LoopFileFullPath)
                    notDir++ , souceFile2 := A_LoopFileFullPath
                if notDir = 2
                    break
            }

            if count = 1 || notDir = 1	;只有一个文件或文件夹
            {
                if notDir = count	;单个文件夹包含单个文件
                    souceFile := souceFile2

                isDir := DirExist(souceFile)
                SplitPath(souceFile, &name, , &ext)

                outFile := this.MoveItem(souceFile, A_WorkingDir "\" name, isDir, A_LineNumber)

                this.RecycleItem(tmpDir, A_LineNumber, true)

                if !this.nesting || !this.nestingMuilt
                    continue

                if !isDir
                {
                    if this.nesting
                        UnZipNesting(outFile, ext)
                } else if this.nestingMuilt
                    loop files outFile "\*.*", "F"
                        UnZipNesting(A_LoopFileFullPath, A_LoopFileExt)

            } else	;多个文件
            {
                SplitPath(i, , , , &nameNoEXT)
                outFile := this.MoveItem(tmpDir, A_WorkingDir "\" nameNoEXT, 1, A_LineNumber)

                if this.nestingMuilt
                    loop files outFile "\*.*", "F"
                        UnZipNesting(A_LoopFileFullPath, A_LoopFileExt)
            }
        }

        if loopPath
            return

        if this.autoRemovePass && (this.dynamicPassSort || this.autoAddPass)
        {
            if this.dynamicPassSort
                PasswordSort

            for i in this.dynamicPassArr
                if A_Index > this.autoRemovePass
                    PasswordClear(A_Index, true)

            if this.dynamicPassArr.Length > this.autoRemovePass
                this.dynamicPassArr.RemoveAt(this.autoRemovePass + 1, this.dynamicPassArr.Length - this.autoRemovePass)
        } else if this.dynamicPassSort
            PasswordSort

        ;执行解压
        zipx(path)
        {
            if this.logLevel
                this.log .= '`n#####`n' path '`n'

            pass := ""
            this.continue := false

            for i in this.password
            {
                if A_Index = 1
                {
                    this.isFile := this.isCmdReturn := false
                    this.needPass := 4
                    cmdArgs := this.7z ' l -slt -bsp1  "' path '"'
                    if this.cmdLog
                        this.testLog .= '`n#####`n' cmdArgs '`n'
                    this.RunCmd(cmdArgs, , CheckEncrypted)

                    switch this.needPass
                    {
                        case 0: break
                        case 1: continue
                        case 2:
                        {
                            for n in this.password
                            {
                                if n
                                {
                                    this.isFile := this.isCmdReturn := false
                                    this.needPass := 5
                                    cmdArgs := this.7z ' l -slt -bsp1 -p"' n '" "' path '"'
                                    this.RunCmd(cmdArgs, , CheckEncrypted)
                                    if this.cmdLog
                                        this.testLog .= '`n#####`n' cmdArgs '`n'
                                    if this.needPass = 1
                                    {
                                        this.error := 0
                                        pass := ' -p"' AddPass(n) '"'
                                        break 2
                                    }
                                }
                            }
                        }
                        case 3: return
                    }
                }

                this.CheckCMD(, this.7z ' t -bsp1 "' path '" -p"' i '"')

                if this.continue
                    return

                if !this.error
                {
                    if i
                        pass := ' -p"' AddPass(i) '"'
                    break
                }
            }

            if !this.needPass || !this.error	;密码正确或无需密码
            {
                this.Run7z(hideBool, 'x', path, '" -aou -o' tmpDir pass this.excludeArgs this.codePage, hideBool || this.guiShow, () => IsSuccess(), A_LineNumber)

                if IsSuccess()
                {
                    if part != -1
                        return
                    if loopPath
                        this.RecycleItem(path, A_LineNumber, true)
                    else if this.delSource || (pass && this.delWhenHasPass)
                        this.RecycleItem(path, A_LineNumber)
                }
            } else
            {
                this.tryPasssword := ""
                if this.autoAddPass
                    SetTimer(TrackPass, 10)
                this.Run7z(false, 'x', path, '" -aou -o' tmpDir this.excludeArgs this.codePage, , () => IsSuccess(), A_LineNumber)
                SetTimer(TrackPass, 0), ToolTip()

                if this.tryPasssword && this.exitCode != 255
                {
                    this.error := true
                    this.CheckCMD(, this.7z ' t -bsp1 "' path '" -p"' this.tryPasssword '"')
                    if !this.error
                        AddPass(this.tryPasssword)
                }

                if IsSuccess() && part = -1 && this.delWhenHasPass
                    this.RecycleItem(path, A_LineNumber)	;密码错误需手动输入密码
            }

            TrackPass()
            {
                title := "ahk_pid " this.pid
                if WinExist(title) && WinActive(title)
                {
                    try
                        if InStr(ControlGetText("Button1", title), "&S")
                        {
                            if !ControlGetChecked("Button1", title)
                                return (this.tryPasssword := "", ToolTip())
                        } else if !ControlGetText("Static14", title)
                            return (SetTimer(TrackPass, 0), ToolTip())

                    try
                        if (str := ControlGetText("Edit1", title))
                            this.tryPasssword := str

                    try
                        if ControlGetText("Static14", title)
                            this.tryPasssword := ""

                    if this.tryPasssword
                        ToolTip "当前密码 : " this.tryPasssword
                } else
                    ToolTip()
            }

            AddPass(pass)
            {
                static notLoopPass := ""	;用以确保嵌套和源文件同密码时不会重复记录

                if !pass
                    return

                if !loopPath
                    notLoopPass := pass
                else if pass = notLoopPass
                    return pass

                if ini.lastPass != pass
                    ini.Write(pass, "lastPass", "temp")

                if this.dynamicPassSort || this.autoAddPass
                {
                    if !this.passwordMap.Has(pass) && this.password.Length > 2 && this.password[3] = pass
                        return pass

                    if !this.passwordMap.Has(pass)
                    {
                        this.dynamicPassArr.Push([pass, 0]), this.passwordMap[pass] := this.dynamicPassArr.Length
                        if this.autoAddPass
                            ini.Write(pass, this.passwordMap.Count, "password")
                    } else
                        this.dynamicPassArr[this.passwordMap[pass]][2]++
                }
                return pass
            }

            CheckEncrypted(LineNum, Line)
            {
                if this.isCmdReturn
                    return

                if this.cmdLog
                    this.testLog .= "[" LineNum "] " line '`n'

                if !this.isFile && InStr(Line, "Attributes = A") || Line ~= "CRC = [A-Z0-9]+"
                    this.isFile := true
                else if this.isFile && InStr(Line, "Attributes = D") || Line ~= "CRC = *?$"
                    this.isFile := false
                else if this.isFile && InStr(Line, "Encrypted = -")
                    LogAndReturn(0, A_LineNumber)

                else if InStr(Line, "Encrypted = +") || InStr(Line, "Wrong password?")
                    LogAndReturn(1, A_LineNumber)
                else if InStr(Line, "Enter password (will not be echoed):")
                    LogAndReturn(2, A_LineNumber)
                else if this.needPass = 5 && InStr(Line, "Errors: 1")
                    LogAndReturn(2, A_LineNumber)
                else if InStr(Line, "Errors: 1") || InStr(Line, "Cannot open the file as archive") || InStr(Line, "Unexpected end of archive")
                    this.continue := true, LogAndReturn(3, A_LineNumber)

                LogAndReturn(num := "", logLineNum := "")
                {
                    this.isCmdReturn := true
                    this.needPass := num
                    ProcessClose(this.CMDPID), ProcessWaitClose(this.CMDPID)
                    this.CMDPID := 0
                    this.Loging(cmdArgs '`n[' LineNum '] ' line, logLineNum, this.needPass > 2 ? 3 : 4)
                }
            }

            IsSuccess()
            {
                if !this.exitCode
                    return true

                if !DirExist(tmpDir)
                    return false

                if this.exitCode != 255
                {
                    folderSize := this.fileSystemObject.GetFolder(tmpDir).Size
                    this.Loging("文件大小: " this.currentSize " 临时文件夹大小: " folderSize, A_LineNumber)

                    if folderSize >= this.currentSize
                        return true
                    else if folderSize / this.currentSize * 100 > this.succesSpercent
                        return true
                }

                this.RecycleItem(tmpDir, A_LineNumber, true)
                return false
            }
        }

        ;解压嵌套
        UnZipNesting(path, ext)
        {
            if !this.IsArchive(ext) || !(part := IsPart(path))
                return

            timeSave := FileGetTime(path), sizeSave := FileGetSize(path)
            this.exitCode := -1
            this.Unzip(path)
            this.Loging("解压嵌套 <--> " path, A_LineNumber)

            if !this.exitCode && part = -1 && FileExist(path) && FileGetTime(path) = timeSave && FileGetSize(path) = sizeSave	;!exitCode &&
                this.RecycleItem(path, A_LineNumber)
        }

        ; 解压后处理
        AfterUnzip(path)
        {
            static isRead := false, obj := { rename: { ext: Map(), name: Map(), exp: Map() },
                deleteExp: [] }

            if !isRead
            {
                ini.ReadLoop("renameExt", obj.rename.ext, , true)
                ini.ReadLoop("renameName", obj.rename.name, , true)
                ini.ReadLoop("renameExp", obj.rename.exp, , true)
                ini.ReadLoop("deleteExp", obj.deleteExp)

                isRead := true
            }

            if (isDir := DirExist(path)) && this.fileSystemObject.GetFolder(path).Size = 0	;空文件夹
                return this.RecycleItem(path, A_LineNumber)

            SplitPath(path, &name, &dir, &ext, &nameNoExt)

            for i in obj.deleteExp
                if name ~= i
                    return this.RecycleItem(path, A_LineNumber)

            for ori, out in obj.rename.ext
            {
                if !isDir && ext = ori
                {
                    name := nameNoExt '.' out
                    break
                }
            }

            for needle, replaceText in obj.rename.name
                if InStr(name, needle)
                    name := StrReplace(name, needle, replaceText)

            for needle, replaceText in obj.rename.exp
                if name ~= needle
                    name := RegExReplace(name, needle, replaceText)

            if path != dir "\" name
                this.MoveItem(path, dir "\" name, isDir, A_LineNumber)
        }

        IsPart(path)
        {
            SplitPath(path, &name)

            if name ~= "i)\.part\d+\.rar$"
            {
                if name ~= "i)\.part0*1\.rar$"	;第一卷
                    return 1
                this.Loging("可能是分卷包  <--> " path, A_LineNumber, 5)
                return 0
            } else if name ~= "\..+\.\d+$"
            {
                if name ~= "\..+.0+1"	;第一卷
                    return 1
                this.Loging("可能是分卷包  <--> " path, A_LineNumber, 5)
                return 0
            }
            return -1
        }

        PasswordSort()
        {
            ;排序
            i := 0
            while (++ i <= this.dynamicPassArr.Length)
            {
                j := 0
                while (++ j <= this.dynamicPassArr.Length - i)
                {
                    if this.dynamicPassArr[j][2] < this.dynamicPassArr[j + 1][2]
                    {
                        temp := this.dynamicPassArr[j]
                        this.dynamicPassArr[j] := this.dynamicPassArr[j + 1]
                        this.dynamicPassArr[j + 1] := temp
                    }
                }
            }

            for i in this.dynamicPassArr
            {
                if ini.Read("A_Index", , "passwordSort") != i[2]
                    ini.Write(i[2], A_Index, "passwordSort")

                if ini.Read("A_Index", , "password") != i[1]
                    ini.Write(i[1], A_Index, "password")
            }

            arr := []
            loop	;清除重复密码
            {
                if (pwd := ini.Read(this.dynamicPassArr.Length + A_Index))
                {
                    if !this.passwordMap.Has(pwd)
                        arr.Push(pwd)
                    PasswordClear(this.dynamicPassArr.Length + A_Index, true)
                } else
                    break
            }

            ; if arr.Length
            ;     for i in arr
            ;         ini.Write(i, this.dynamicPassArr.Length + A_Index, "password")
        }

        PasswordClear(index, delete := false)
        {
            if delete
                IniDelete(ini, "password", index), IniDelete(ini, "passwordSort", index)
            else
                ini.Write(, index, "password"), ini.Write(, index, "passwordSort")
        }

        FormatPassword(str) => StrLen(str) < 100 ? Trim(RegExReplace(str, "(\R*)")) : ""	;移除所有换行符及首尾所有空格或制表符
    }

    OpenZip()
    {
        SplitPath(this.arr[1], , &dir, &ext, &nameNoExt)

        if !this.muilt
        {
            extForOpen := Map()
            ini.ReadLoop("extForOpen", extForOpen, true)

            path := ' "' this.arr[1] '" '

            If DirExist(this.arr[1])
                this.error := true
            else if (this.IsArchive(ext) || extForOpen.Has(ext))
                this.error := false
            else
            {
                if this.logLevel
                    this.log .= '`n#####`n' this.arr[1] '`n'
                this.CheckCMD("openZip", this.7z ' l ' path)
            }

            if !this.error
            {
                Run(this.7zFM path, , , &pid)
                this.Loging("打开 <--> " path, A_LineNumber)
            }
        }

        if this.muilt || this.error
        {
            args := ini.openAdd
            path := ""
            for i in this.arr
                path .= ' "' i '" '
            zipName := this.muilt ? StrReplace(RegExReplace(A_WorkingDir, ".+\\"), ":") : DirExist(this.arr[1]) ? RegExReplace(this.arr[1], ".+\\") : nameNoExt
            ext := RegExReplace(args, '(.+?)".*', "$1")
            this.Run7z(, 'a', this.AUO(zipName, ext), args path, , , A_LineNumber)
        }
    }

    CreateZip()
    {
        SplitPath(this.arr[1], , , , &nameNoExt)

        count := 0
        for i in this.arr
            if DirExist(i)
                count++
        hideBool := IsHide()

        args := ini.add
        ext := RegExReplace(args, '(.+?)".*', "$1")

        if count = this.arr.Length	;全是文件夹,单独添加
        {
            for i in this.arr
            {
                hideBool := IsHide(i)
                if count > 1 && !hideBool && !this.guiShow
                    this.Gui
                zipName := this.AUO(RegExReplace(i, ".*\\"), ext)
                this.temp := zipName ext
                this.index := A_Index
                this.Run7z(hideBool, 'a', zipName, args ' "' i '\*"', hideBool || count > 1, , A_LineNumber)

            }
            return

        } else if this.arr.Length = 1	;单个文件
            this.Run7z(hideBool, 'a', this.AUO(nameNoExt, ext), args ' "' this.arr[1] '"', hideBool, , A_LineNumber)
        else	;文件文件夹混合
        {
            for i in this.arr
                path .= ' "' i '" '
            this.Run7z(hideBool, 'a', this.AUO(RegExReplace(A_WorkingDir, ".+\\"), ext), args path, hideBool, , A_LineNumber)
        }

        IsHide(dir := "")
        {
            countSzie := 0
            if dir
            {
                loop files dir "\*.*", "RDF"
                    if (countSzie += A_LoopFileSizeMB) > this.hideRunSize
                        return false
                return true
            }

            for i in this.arr
            {
                if DirExist(i)
                {
                    loop files i "\*.*", "RDF"
                        if (countSzie += A_LoopFileSizeMB) > this.hideRunSize
                            return false
                } else
                    countSzie += FileGetSize(i, "M")
                if countSzie > this.hideRunSize
                    return false
            }
            return true
        }
    }

    Gui()
    {
        this.guiShow := true
        DetectHiddenWindows(1)

        g := Gui("+LastFound")
        DllCall("RegisterShellHookWindow", "UInt", WinExist())
        msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
        OnMessage(msgNum, ShellMessage)

        g.SetFont(, "Segoe UI")
        g.BackColor := "FFFFFF"

        已用时间1 := g.Add("text", "w100"), 已用时间2 := leftVaule()
        总大小1 := rightTitle(), 总大小2 := rightVaule()

        剩余时间1 := leftTitle(), 剩余时间2 := leftVaule()
        速度1 := rightTitle(), 速度2 := rightVaule()

        文件1 := leftTitle(), 文件2 := leftVaule()
        已处理1 := rightTitle(), 已处理2 := rightVaule()

        leftTitle(), 文件3 := leftVaule()
        压缩后大小1 := rightTitle(), 压缩后大小2 := rightVaule()

        总进度1 := leftTitle(), 总进度2 := leftVaule()
        压缩率1 := rightTitle(), 压缩率2 := rightVaule()

        g.Add("text", "h1 w1")

        处理1 := g.Add("text", "xs w500")
        if this.to = "x"
            处理2 := g.Add("text", "w500")
        处理3 := g.Add("text", "w500")
        进度 := g.Add("Progress", "w500 h20")

        leftTitle() => g.Add("text", "xs w100")
        leftVaule() => g.Add("text", "yp w100 x120 Right")
        rightTitle() => g.Add("text", "yp w100 x300")
        rightVaule() => g.Add("text", "yp w100 x420 Right")

        g.Add("text")

        g.AddButton("w100 x10", "显示原始界面").OnEvent("Click", ButtonShowHide)
        暂停 := g.AddButton("x300 w100 yp")
        暂停.OnEvent("Click", ButtonPause)
        取消 := g.AddButton("w100 yp")
        取消.OnEvent("Click", ButtonCance)

        g.OnEvent("Close", Close)
        g.OnEvent("Escape", Close)

        sub() => "ahk_pid " this.pid
        g.Show("AutoSize")

        Close(*)
        {
            if ProcessExist(this.pid)
                ProcessClose(this.pid), ProcessWaitClose(this.pid)
            if this.HasOwnProp("temp")
                this.RecycleItem(this.temp, A_LineNumber, true)
            if !this.setShow
                ExitApp(255)
            OnMessage(msgNum, ShellMessage, 0), g.Destroy()
        }

        ButtonShowHide(GuiCtrlObj, *)
        {
            DetectHiddenWindows(0)
            if !ProcessExist(this.pid)
                return

            if WinExist(sub())
                WinHide(sub()), GuiCtrlObj.Text := "显示原始界面"
            else
                WinShow(sub()), WinActivate(sub()), GuiCtrlObj.Text := "隐藏原始界面"
        }

        ButtonPause(GuiCtrlObj, Info)
        {
            DetectHiddenWindows(1)
            if !WinExist(sub())
                return

            textSave := GuiCtrlObj.Text
            ControlClick("Button2", sub())
            ShellMessage
            while WinExist(sub()) && GuiCtrlObj.Text = textSave
                ControlClick("Button2", sub()), Sleep(500), ShellMessage()
        }

        ButtonCance(GuiCtrlObj, Info)
        {
            DetectHiddenWindows(1)
            if !WinExist(sub())
                return
            ControlClick("Button3", sub())
            ShellMessage
            while WinExist(sub()) && !InStr(WinGetText(sub()), "否(&N)")
                ControlClick("Button3", sub()), Sleep(500)

            WinWaitActive(sub())
            WinWaitClose
            num := 0
            loop 5
                if !WinExist(sub())
                    num++

            if num = 5
                Close
        }

        DetectError()
        {
            DetectHiddenWindows(0)
            if WinExist(sub())
                return
            else
                WinShow(sub())
        }

        ShellMessage(wParam := 6, *)
        {
            ListLines(0)
            DetectHiddenWindows(1)
            static timeSave := A_TickCount

            if !this.isRunning
                Close()

            if A_TickCount - timeSave < 50 || wParam != 6 || !WinExist(sub())
                return

            IsChanged(总进度1, "总进度:")
            , IsChanged(总进度2, this.index "\" this.arr.Length)
            try
            {
                if g.Title != WinGetTitle(sub())
                    g.Title := WinGetTitle(sub())

                arr := StrSplit(WinGetText(sub()), "`n")
                for i in arr
                {
                    if InStr(i, "您真的要取消吗")
                        return
                    arr[A_Index] := SubStr(i, 1, -1)
                }

                IsChanged(进度, RegExReplace(g.Title, "(.+ )?(\d+)%.+", "$2"))
                , IsChanged(暂停, arr[2], 1)
                , IsChanged(取消, arr[3], 1)

                , IsChanged(已用时间1, arr[4])
                , IsChanged(剩余时间1, arr[5])
                , IsChanged(文件1, arr[6])

                ; IsChanged(发生错误, arr[7])

                IsChanged(总大小1, arr[8])
                , IsChanged(速度1, arr[9])
                , IsChanged(已处理1, arr[10])
                , IsChanged(压缩后大小1, arr[11])
                , IsChanged(压缩率1, arr[12])

                , IsChanged(已用时间2, arr[13])
                , IsChanged(剩余时间2, arr[14])
                , IsChanged(文件2, arr[15])

                index := 16

                if this.to = "a"
                    IsChanged(文件3, arr[index++ ])

                if IsNumber(arr[index++ ])	;发生错误
                    DetectError()	; IsChanged(发生错误2, arr[index -1])
                else
                    index--

                IsChanged(总大小2, arr[index++ ])	;16
                , IsChanged(速度2, arr[index++ ])	;17
                , IsChanged(已处理2, arr[index++ ])	;18
                , IsChanged(压缩后大小2, arr[index++ ])	;19
                , IsChanged(压缩率2, arr[index++ ])	;20

                , IsChanged(处理1, arr[index++ ])	;21

                index++
                if this.to = "x"
                    IsChanged(处理2, arr[index - 1])	;22

                IsChanged(处理3, arr[index])	;23
            }
            timeSave := A_TickCount
            ListLines(1)
            IsChanged(obj, value, text := 0)
            {
                if !text
                {
                    if obj.Value != value
                        obj.Value := value
                } else if obj.Text != value
                    obj.Text := value
            }
        }
    }

    Run7z(is7z := false, xa := "x", path := "", args := "", hide := false, log := true, linenum := "")
    {
        this.pid := ""
        this.cmdHide := false
        if !is7z
            SetTimer(WinGetPID, 10)
        else if !this.guiShow
            this.cmdHide := true
        this.exitCode := RunWait((is7z ? this.7z : this.7zG) ' ' xa ' "' path args, , hide ? "hide" : "")

        SetTimer(WinGetPID, 0)
        if log
            this.Loging('[' this.exitCode '] ' (xa = 'x' ? "解压" : "压缩") " <--> " path, linenum)

        WinGetPID()
        {
            DetectHiddenWindows(1)
            static winmgmts := ComObjGet("winmgmts:")

            WinWait("ahk_exe 7zG.exe", , 3)
            winmgmts.ExecQuery('Select * from Win32_Process where Name="7zG.exe" and CommandLine like "%' StrReplace(path, "\", "\\") '%"')._NewEnum()(&proc)
            if (this.pid := IsSet(proc) ? proc.ProcessID : "")
            {
                if this.to = "x" && this.excludeArgs
                {

                    while (!GetSize())
                    {
                        if A_TickCount - this.now > 1000
                            break
                    }
                    if RegExMatch(GetSize(), "(.+) MB$", &size)
                        this.currentSize := size[1] * 1024 * 1024
                }
                SetTimer(WinGetPID, 0)
            }

            GetSize()
            {
                size := ""
                try
                    size := ControlGetText("Static15", "ahk_pid " this.pid)
                return size
            }
        }
    }

    RecycleItem(souce, lineNum, delete := false)
    {
        try
        {
            if delete
                DirExist(souce) ? DirDelete(souce, 1) : FileDelete(souce)
            else
                FileRecycle(souce)
            this.Loging(souce, lineNum, 1)
        }
    }

    MoveItem(souce, dest, isdir, lineNum)
    {
        try
        {
            (isDir ? DirMove : FileMove)(souce, oPath := this.PathDupl(dest, isdir))
            this.Loging(souce " <--> " oPath, lineNum, 2)
            return oPath
        } catch
            return souce
    }

    AUO(name, ext) => StrReplace(this.PathDupl(A_WorkingDir "\" name ext, 0), ext)

    PathDupl(path, isdir := 0)
    {
        if FileExist(path)	;目标文件重复
        {
            SplitPath(path, , &dir, &ext, &nameNoExt)

            if isdir && ext	;文件夹包含.被识别为文件  示例 " D:\1.2"
                nameNoExt := RegExReplace(path, ".*\\")

            ext := (isdir || !ext) ? "" : "." ext	;目标为文件夹 或 目标为文件但无 ext 时 ext 为空
            while FileExist(path)
                path := dir '\' nameNoExt '_' A_Index ext
        }

        return path
    }

    IsArchive(ext)
    {
        ext := StrLower(ext)

        if !ext
            return true

        if this.ext.Has(ext)
            return true

        for i, n in this.ext
            if InStr(i, ext)
                return true

        for i in this.extExp
            if ext ~= "i)" i
                return true

        return false
    }

    ;https://www.autohotkey.com/boards/viewtopic.php?t=93944
    RunCmd(CmdLine, Codepage := "CP0", fn := "") {
        DllCall("CreatePipe", "PtrP", &hPipeR := 0, "PtrP", &hPipeW := 0, "Ptr", 0, "Int", 0)
        , DllCall("SetHandleInformation", "Ptr", hPipeW, "Int", 1, "Int", 1)
        , DllCall("SetNamedPipeHandleState", "Ptr", hPipeR, "UIntP", &PIPE_NOWAIT := 1, "Ptr", 0, "Ptr", 0)

        , P8 := (A_PtrSize = 8)
        , SI := Buffer(P8 ? 104 : 68, 0)	; STARTUPINFO structure
        , NumPut("UInt", P8 ? 104 : 68, SI)	; size of STARTUPINFO
        , NumPut("UInt", STARTF_USESTDHANDLES := 0x100, SI, P8 ? 60 : 44)	; dwFlags
        , NumPut("Ptr", hPipeW, SI, P8 ? 88 : 60)	; hStdOutput
        , NumPut("Ptr", hPipeW, SI, P8 ? 96 : 64)	; hStdError
        , PI := Buffer(P8 ? 24 : 16)	; PROCESS_INFORMATION structure

        If !DllCall("CreateProcess", "Ptr", 0, "Str", CmdLine, "Ptr", 0, "Int", 0, "Int", True, "Int", 0x08000000 | DllCall("GetPriorityClass", "Ptr", -1, "UInt"), "Int", 0
            , "Ptr", 0, "Ptr", SI.ptr, "Ptr", PI.ptr)
            Return Format("{1:}", "", -1, DllCall("CloseHandle", "Ptr", hPipeW), DllCall("CloseHandle", "Ptr", hPipeR))

        DllCall("CloseHandle", "Ptr", hPipeW)
        , this.CMDPID := NumGet(PI, P8 ? 16 : 8, "UInt")
        , File := FileOpen(hPipeR, "h", Codepage)
        , LineNum := 1, sOutput := ""

        While (this.CMDPID + DllCall("Sleep", "Int", 0)) && DllCall("PeekNamedPipe", "Ptr", hPipeR, "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0)
            While this.CMDPID && !File.AtEOF
                Line := File.ReadLine(), sOutput .= fn ? Fn.Call(LineNum++ , Line) : this.CheckCMD(LineNum++ , Line)

        this.CMDPID := 0
        , hProcess := NumGet(PI, 0, "Ptr")
        , hThread := NumGet(PI, A_PtrSize, "Ptr")

        , DllCall("CloseHandle", "Ptr", hProcess)
        , DllCall("CloseHandle", "Ptr", hThread)
        , DllCall("CloseHandle", "Ptr", hPipeR)

        Return sOutput
    }

    CheckCMD(what := "unZip", line := "")
    {
        static check, checkSave := "", whatSave := what, cmdArgs

        if Type(what) = "String"
        {
            if !checkSave
            {
                ; checkSave := { error: Map(), errorExp: Map(), errorrContinueExp: Map(), success: Map(), successExp: Map() }
                checkSave := { error: Map(), errorExp: Map(), success: Map(), successExp: Map() }
                ini.ReadLoop(what "CheckError", checkSave.error, , true)
                ini.ReadLoop(what "CheckErrorExp", checkSave.errorExp, , true)
                ; ini.ReadLoop(what "CheckErrorContinueExp", checkSave.errorrContinueExp, , true)
                ini.ReadLoop(what "CheckSuccess", checkSave.success, , true)
                ini.ReadLoop(what "CheckSuccessExp", checkSave.successExp, , true)
            }
            check := {}
            for i in checkSave.OwnProps()
                check.%i% := checkSave.%i%.Clone()

            this.isCmdReturn := false
            this.error := true
            cmdArgs := line
            if this.cmdLog
                this.testLog .= '`n#####`n' cmdArgs '`n'

            this.RunCmd(cmdArgs)

        } else if line
        {
            if this.isCmdReturn
                return

            if this.cmdLog
                this.testLog .= "[" what "] " line '`n'

            ; for i in check.errorrContinueExp
            ;     if line ~= i && --check.errorrContinueExp[i] < 1
            ;         return (this.continue := true, LogAndReturn(1, A_LineNumber))

            for i in check.error
                if InStr(line, i) && --check.error[i] < 1
                    return LogAndReturn(2, A_LineNumber)

            for i in check.errorExp
                if line ~= i && --check.errorExp[i] < 1
                    return LogAndReturn(3, A_LineNumber)

            for i in check.success
                if InStr(line, i) && --check.success[i] < 1
                    return LogAndReturn(4, A_LineNumber)

            for i in check.successExp
                if line ~= i && --check.successExp[i] < 1
                    return LogAndReturn(5, A_LineNumber)

            if whatSave = "unZip" && (line ~= "^ +[1-9]+%") && !(line ~= "^ +[1-9]+%.+Open$" || line ~= "^ +[1-9]+%$")
                return LogAndReturn(6, A_LineNumber)

            LogAndReturn(num, lineNum)
            {
                this.isCmdReturn := true
                ProcessClose(this.CMDPID), ProcessWaitClose(this.CMDPID)
                this.CMDPID := 0
                if num < 4
                    this.error := 1
                else
                    this.error := 0
                this.Loging(cmdArgs "`n[" what '] ' line, lineNum, this.error ? 3 : 4)
            }
        }
    }

    ; 关闭0/删除1/重命名2/命令行错误3/命令行正确4/其他5
    Loging(log, lineNum, level := 5)
    {
        if !this.logLevel || level > this.logLevel
            return

        switch level
        {
            case 5: msg := "其他"
            case 4: msg := "命令行正确"
            case 3: msg := "命令行错误"
            case 2: msg := "重命名"
            case 1: msg := "删除"
        }

        this.log .= Format("[{1}] [{2}] [{3}ms] [{4}]`n{5}", msg, lineNum, A_TickCount - this.now, FormatTime(A_Now, "yyyy/M/d H:m:s"), log) '`n'
        this.now := A_TickCount
    }
}

Setting()
{
    ; Modern edition: configuration only. Shell registration belongs to the installer.
    Run('notepad.exe "' ini.path '"')
    ExitApp()
}

WM_MOUSEMOVE(wParam, lParam, msg, Hwnd)
{
    ListLines(0)
    static PrevHwnd := 0
    if (Hwnd != PrevHwnd)
    {
        static PrevHwnd := 0
        static HoverControl := 0
        currControl := GuiCtrlFromHwnd(Hwnd)
        if (Hwnd != PrevHwnd)
        {
            Text := "", ToolTip()
            if CurrControl
            {
                if !CurrControl.HasProp("ToolTip")
                    return
                SetTimer(CheckHoverControl, 50)
                SetTimer(DisplayToolTip, -700)
            }
            PrevHwnd := Hwnd
        }
        return
        CheckHoverControl() => hwnd != prevHwnd ? (SetTimer(DisplayToolTip, 0), SetTimer(CheckHoverControl, 0)) : ""
        DisplayToolTip() => (ToolTip(CurrControl.ToolTip), SetTimer(CheckHoverControl, 0))
    }
    ListLines(1)
}


class ini
{
    static map := {
            zipDir: ["", "set"],
            icon: ["", "set"],
            targetDir: ["", "set"],
            delSource: [0, "set"],
            delWhenHasPass: [0, "set"],
            successPercent: [0, "set"],
            logLevel: [0, "set"],
            nesting: [0, "set"],
            nestingMuilt: [0, "set"],
            hideRunSize: [0x7FFFFFFFFFFFFFFF, "set"],
            cmdLog: [0, "set"],
            dynamicPassSort: [0, "set"],
            test: [0, "set"],
            partSkip: [0, "set"],
            autoRemovePass: [0, "set"],
            autoAddPass: [0, "set"],
            openZipName: ["", "menu"],
            unZipName: ["", "menu"],
            unZipCPName: ["", "menu"],
            addZipName: ["", "menu"],
            add: ["", "7z"],
            openAdd: ["", "7z"],
            lastPass: ["", "temp"],
            version: [0, "temp"],
        }

    static __Get(Key, Params)
        {
            if this.map.HasProp(key)
                return this.Read(key, this.map.%key%[1], this.map.%key%[2])
        }

    static Init(path) => this.path := path

    static Read(Key, default := "", section := "") => IniRead(this.path, section, key, default)

    static setWrite(key, value := "") => this.Write(value, key, this.map.%key%[2])

    static Write(value := "", Key := "", section := "")
        {
            static sectionSave := section
            if section
                sectionSave := section
            IniWrite(value, this.path, sectionSave, key)
        }

    static Delete(section, key)
        {
            IniDelete(this.path, section, key)
        }

    static ReadLoop(Section, arrMap, lower := false, twoVar := false)
    {
        loop
        {
            if !(var := this.Read(A_Index, , Section))
                break

            if lower
                var := StrLower(var)

            if Type(arrMap) = "Array"
                arrMap.Push(var)
            else if Type(arrMap) = "Map"
            {
                if twoVar
                    arrMap[RegExReplace(var, "<--->.*")] := RegExReplace(var, ".+<--->")
                else
                    arrMap[var] := true
            }
        }
        if Type(arrMap) = "Array"
        {
            loop
            {
                if arrMap.Length < A_Index
                    break

                var := arrMap[A_Index]
                temp := []
                for i in arrMap
                    if var = i
                        temp.Push(A_Index)

                temp.RemoveAt(1)
                loop temp.Length
                    arrMap.RemoveAt(temp[temp.Length - A_Index + 1])
            }
        }
    }
}

RelativePath(str) => StrReplace(str, "%SmartZipDir%", A_ScriptDir)

IniCreate()
{
    iniExist := FileExist(ini.path)
    version := ini.version
    VersionsCompare(num) => !iniExist || version < num

    if !iniExist
    {
        ini.setWrite("zipDir", "%SmartZipDir%\..\Backend")
        ini.setWrite("icon", "%SmartZipDir%\..\Assets\SmartZip.ico")
        ini.setWrite("nesting", 1)
        ini.setWrite("nestingMuilt", 0)
        ini.setWrite("partSkip", 1)
        ini.setWrite("delSource", 0)
        ini.setWrite("delWhenHasPass", 0)
        ini.setWrite("autoAddPass", 0)
        ini.setWrite("dynamicPassSort", 0)
        ini.setWrite("autoRemovePass", 0)
        ini.setWrite("targetDir")
        ini.setWrite("test", 0)
        ini.setWrite("successPercent", 90)
        ini.setWrite("logLevel", 0)
        ini.setWrite("cmdLog", 0)
        ini.setWrite("hideRunSize", 10)

        ini.Write(0, "addDir2Pass", "set")

        ini.Write(, 1, "password")

        ini.setWrite("openZipName", "用7-Zip打开")
        ini.setWrite("unZipName", "智能解压")
        ini.setWrite("unZipCPName", "手动指定代码页解压")
        ini.setWrite("addZipName", "压缩")

        ini.Write("zip", 1, "ext")
        ini.Write("rar", 2)
        ini.Write("7z", 3)
        ini.Write("001", 4)
        ini.Write("cab", 5)
        ini.Write("bz2", 6)
        ini.Write("gz", 7)
        ini.Write("gzip", 8)
        ini.Write("tar", 9)

        ini.Write("^\d+$", 1, "extExp")
        ini.Write("zi", 2)
        ini.Write("7", 3)
        ini.Write("z", 4)

        ini.Write("iso", 1, "extForOpen")
        ini.Write("apk", 2)
        ini.Write("wim", 3)
        ini.Write("exe", 4)

        ini.Write("", 1, "renameExt")

        ini.Write("", 1, "renameName")

        ini.Write("", 1, "renameExp")

        ini.Write(, 1, "excludeExt")

        ini.Write(, 1, "excludeName")

        ini.Write(, 1, "deleteExp")

        ini.setWrite("openAdd", '.zip" -tzip -mx=0 -aou -ad')
        ini.setWrite("add", '.zip"')

        ini.Write("Wrong password<--->1", 1, "unZipCheckError")
        ini.Write("Cannot open encrypted archive<--->1", 2)
        ini.Write("No files to process<--->1", 3)
        ini.Write("ERROR:<--->10", 4)

        ini.Write(, 1, "unZipCheckErrorExp")

        ; ini.Write("Errors: 1<--->1", 1, "unZipCheckErrorContinueExP")
        ; ini.Write("Data Error :<--->1", 2)
        ; ini.Write("Cannot open the file as archive<--->1", 3)

        ini.Write("Everything is Ok<--->1", 1, "unZipCheckSuccess")

        ini.Write(, 1, "unZipCheckSuccessExp")

        ini.Write("Errors: 1<--->1", 1, "openZipCheckError")
        ini.Write("ERROR:<--->1", 2)

        ini.Write(, 1, "openZipCheckErrorExp")

        ini.Write("Enter password (will not be echoed):<--->1", 1, "openZipCheckSuccess")	;需要输入密码则可能是压缩文件

        ini.Write("\d*-\d*-\d* *\d*:\d*:\d* *\d* *\d* *(\d*) files(, (\d*) folders)?<--->1", 1, "openZipCheckSuccessExp")	;多少个文件多少个文件夹则可能是压缩文件
    }

    if VersionsCompare(buildVersion)
        ini.setWrite("version", buildVersion)
}
