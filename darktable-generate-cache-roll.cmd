:: MIT License
::
:: Copyright (c) 2021 Eric Derewonko
::
:: Permission is hereby granted, free of charge, to any person obtaining a copy
:: of this software and associated documentation files (the "Software"), to deal
:: in the Software without restriction, including without limitation the rights
:: to use, copy, modify, merge, publish, distribute, sublicense, and\or sell
:: copies of the Software, and to permit persons to whom the Software is
:: furnished to do so, subject to the following conditions:
::
:: The above copyright notice and this permission notice shall be included in all
:: copies or substantial portions of the Software.
::
:: THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
:: IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
:: FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
:: AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
:: LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
:: OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
:: SOFTWARE.

@echo OFF
pushd %~dp0

:defaults
:: default values
set min-mip=0
set max-mip=5
call %~dp0\common.cmd
call %~dp0\custom.cmd 2>NUL


:init
:: remember the command line to show it in the end when not purging
set "commandline=%0 %*"

set rolls_list=%TEMP%\darktable-rolls_list.%RANDOM%.tmp
set imgid_list=%TEMP%\darktable-imgid_list.%RANDOM%.tmp


:arguments
:: passed arguments will always override common and custom values
:: also: https://docs.darktable.org/usermanual/3.6/preferences-settings/general/
:: settings > general > prefer performance over quality = FALSE otherwise you will never generate levels above 4

:: handle command line arguments; warning: there is no check when second needed parameter is missing
for %%o in (%*) DO (
  IF /I "%%~o"=="-h"              call :USAGE && goto :end
  IF /I "%%~o"=="-help"           call :USAGE && goto :end
  IF /I "%%~o"=="--help"          call :USAGE && goto :end
  IF /I "%%~o"=="/?"              call :USAGE && goto :end
      
  IF /I "%%~o"=="-l"              call set "library=%%~2" && shift /1
  IF /I "%%~o"=="--library"       call set "library=%%~2" && shift /1
      
  IF /I "%%~o"=="-c"              call set "cachedir=%%~2" && shift /1
  IF /I "%%~o"=="--cachedir"      call set "cachedir=%%~2" && shift /1
    
  IF /I "%%~o"=="-C"              call set "cache_thumbs=%%~2" && shift /1
  IF /I "%%~o"=="--cache_thumbs"  call set "cache_thumbs=%%~2" && shift /1
    
  IF /I "%%~o"=="-d"              call set "configdir=%%~2" && shift /1
  IF /I "%%~o"=="--configdir"     call set "configdir=%%~2" && shift /1
      
  IF /I "%%~o"=="-p"              set dryrun=0
  IF /I "%%~o"=="--purge"         set dryrun=0

  IF /I "%%~o"=="-m"              set "min-mip=%%~2" && shift /1
  IF /I "%%~o"=="-M"              set "max-mip=%%~2" && shift /1

  shift /1
)


:prechecks
:: you cannot concurently access a sqlite database
tasklist /FI "IMAGENAME eq darktable.exe" /FI "STATUS eq running" | findstr darktable.exe && echo error: darktable is running, please exit first && timeout /t 3 && exit /b 1
:: get sqlite3.exe here: https://www.sqlite.org/2017/sqlite-tools-win32-x86-3170000.zip
where sqlite3 >NUL 2>&1 || echo error: sqlite3.exe is not found, please add it somewhere in your PATH first && exit /b 1

:: level 8 = 1:1 size
IF %max-mip% GTR 8 set max-mip=8

:: test configdir:
if NOT EXIST "%configdir%" echo error: configdir "%configdir%" doesn't exist && exit /b 1

:: if you force configdir but not library:
if NOT EXIST "%library%" set library=%configdir%\library.db

:: test library:
if NOT EXIST "%library%" echo error: library db "%library%" doesn't exist && exit /b 1


::::::::::::::::::::::::::::::::::::::::::::::: main
:main
:: necessary for sqlite3 box to display
chcp 65001 >NUL

echo This script will generate missing thumbnails for selected film rolls
echo:

:: display a list of all image rolls from the library and images count
sqlite3 -box "%library%" "select film_rolls.id, film_rolls.folder as roll, count(images.id) as count from film_rolls left join images ON film_rolls.id = images.film_id group by film_rolls.id" >"%rolls_list%"

:: shortcut to exit
for /f %%r IN ("%rolls_list%") DO IF %%~zr EQU 0 echo ERROR: no film rolls in your database yet... & timeout /t 5 & goto :end

type "%rolls_list%"

set    rolls=
set /P rolls=roll(s) to process? 
IF NOT DEFINED rolls exit /b 1
:: replace spaces by commas
set rolls=%rolls: =,%

set /P min-mip=min-mip? [%min-mip%] 
set /P max-mip=max-mip? [%max-mip%] 
IF %min-mip% GTR 8 set min-mip=8
IF %max-mip% GTR 8 set max-mip=8

:: get min-imgid and max-imgid for each roll
del /f /q "%imgid_list%" >NUL 2>&1
sqlite3 -column "%library%" "select film_rolls.id, min(images.id), max(images.id) from film_rolls left join images ON film_rolls.id = images.film_id where film_rolls.id IN (%rolls%) group by film_rolls.id" >"%imgid_list%"

:: process each roll
for /f "tokens=1-3" %%i in (%imgid_list%) DO (
  echo:
  echo Processing roll #%%i ...
  echo ------------------------
  echo call darktable-generate-cache.exe --min-mip %max-mip% --max-mip %max-mip% --min-imgid %%j --max-imgid %%k --core --configdir %configdir% --cachedir %cachedir%
  call darktable-generate-cache.exe --min-mip %max-mip% --max-mip %max-mip% --min-imgid %%j --max-imgid %%k --core --configdir %configdir% --cachedir %cachedir%
)

goto :end
::::::::::::::::::::::::::::::::::::::::::::::: main


:USAGE
echo Delete thumbnails of images that are no longer in darktable's library
echo Usage:   %~n0 [options]
echo:
echo Options:
echo   -c^|--cachedir ^<path^>   path to the place where darktable's cache folder
echo                            (default: "%cachedir%")
echo   -C^|--cache_thumbs ^<path^>   path to the place where darktable's thumbnail caches are stored
echo                            (default: auto-detected "%cachedir%\mipmaps-sha1sum.d")
echo   -d^|--configdir ^<path^>    path to the darktable config directory
echo                            (default: "%configdir%")
echo   -l^|--library ^<path^>      path to the library.db
echo                            (default: "%library%")
echo   -p^|--purge               actually delete the files instead of just finding them
goto :EOF

:end
:: cleanup
del /f /q "%rolls_list%" "%imgid_list%"

REM usage: darktable-generate-cache.exe [-h, --help; --version]
  REM [--min-mip <0-8> (default = 0)] [-m, --max-mip <0-8> (default = 2)]
  REM [--min-imgid <N>] [--max-imgid <N>]
  REM [--core <darktable options>]

REM When multiple mipmap sizes are requested, the biggest one is computed
REM while the rest are quickly downsampled.

REM The --min-imgid and --max-imgid specify the range of internal image ID
REM numbers to work on.