﻿$host.ui.RawUI.WindowTitle = “Start FlytSim”
write-host ("`nThis script is going to start FlytSim session for you.")  -foreground green
write-host ("`nVisit http://localhost/flytconsole in your browser to check connectivity with FlytSim`n`n")  -foreground cyan

$is_new_img="0"
$image_name=$((get-content $PSScriptRoot\docker-compose.yml) | where {$_ -match 'image.+$' }).Trim().Split(" ")[1]
$container_name=$((get-content $PSScriptRoot\docker-compose.yml) | where {$_ -match 'container_name.+$' }).Trim().Split(" ")[1]

function replaceip {
    $localip = $(ipconfig | where {$_ -match 'IPv4.+\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})' } | out-null; $Matches[1])
    (get-content $PSScriptRoot\docker-compose.yml) | foreach-object {$_ -replace "DISPLAY.+$", ("DISPLAY="+$localip+":1.0")} | set-content $PSScriptRoot\docker-compose.yml
}

function is_docker_installed_and_running {
    if (-Not (Get-Command "docker" -errorAction SilentlyContinue))
    {
        Write-Host("`nError: Docker NOT found. Please install docker in your machine. Exiting ...") -ForegroundColor Red
        pause
        exit
    }
    else
    {
        $windowsversion= $((Get-WmiObject -class Win32_OperatingSystem).Caption)
        if ($windowsversion -eq "Microsoft Windows 10 Home")
        {
            Write-Host("`nError: Microsoft Windows 10 Home detected,") -ForegroundColor Red
            Write-Host("Sorry FlytSim is not supported for this version of Windows yet. Upgrade to Windows 10 PRO. Exiting ...`n`n") -ForegroundColor Cyan
            pause
            exit    
        }
        elseif ($windowsversion -match "Microsoft Windows 10")
        {
            Get-Process "docker for windows" -ErrorAction SilentlyContinue | Out-Null
            if ($? -ne "True"){
                Write-Host("`nError: Docker daemon does not seem to be running. Please restart docker in your machine. Exiting ...") -ForegroundColor Red
                pause
                exit
            }
        }
        else 
        {
            Write-Host("`nError: $windowsversion detected,") -ForegroundColor Red
            Write-Host("Sorry FlytSim is not supported for this version of Windows yet. Upgrade to Windows 10 PRO. Exiting ...`n`n") -ForegroundColor Cyan
            pause
            exit
        }
    }
}

function is_xming_installed_and_running {
    if (-Not (Get-Command "xming" -errorAction SilentlyContinue))
    {
        Write-Host("Xming NOT found. Please run setup script. Xming is required to get FlytSIM GUI. Ignore this warning if you don't want GUI") -ForegroundColor Red
        $quit = Read-Host -Prompt 'Do you want to quit and execute setup script? [y/N]'
        if (($quit -eq 'y') -or ($quit -eq 'Y')) {exit}
    }
    else
    {
        Get-Process xming -ErrorAction SilentlyContinue | Out-Null
        if ($? -ne "True"){
            xming :1 -ac -multiwindow
        }
    }
}

function close_ports {
    
    Write-Host("Closing if any process is binded to ports (80,8080,5760)") -ForegroundColor Cyan
    $portPID=$(netstat -ano | Select-String -List ":80" | Select-String "LISTENING" | ConvertFrom-String | select P6 | Select-Object -Unique -ExpandProperty P6)
    if(($portPID.Length -gt 0) -and ($(ps -Id $portPID).ProcessName -ne "com.docker.slirp"))
    {
        Stop-Process $portPID
    }
 
    $portPID=$(netstat -ano | Select-String -List ":8080" | Select-String "LISTENING" | ConvertFrom-String | select P6 | Select-Object -Unique -ExpandProperty P6)
    if(($portPID.Length -gt 0) -and ($(ps -Id $portPID).ProcessName -ne "com.docker.slirp"))
    {
        Stop-Process $portPID
    }
 
    $portPID=$(netstat -ano | Select-String -List ":5760" | Select-String "LISTENING" | ConvertFrom-String | select P6 | Select-Object -Unique -ExpandProperty P6)
    if(($portPID.Length -gt 0) -and ($(ps -Id $portPID).ProcessName -ne "com.docker.slirp"))
    {
        Stop-Process $portPID
    }
}

function do_image_pull {
    Write-Host("Downloading new container image from server, if available") -ForegroundColor Cyan
    $img_sha=$(docker images --format "{{.ID}}" $image_name)
    docker-compose pull
    $img_new_sha=$(docker images --format "{{.ID}}" $image_name)
    if ( "$img_sha" -ne "$img_new_sha" )
	{
		if ( docker ps -a | where {$_ -match $container_name} )
		{
			$Global:is_new_img="1"
            Write-Host("Container image updated, backing up user container in $($image_name.Split(":")[0]):backup") -ForegroundColor Cyan
			docker-compose stop
            docker rmi "$($image_name.Split(":")[0]):backup"
			docker commit -m "backing up user data on $(date)" $container_name "$($image_name.Split(":")[0]):backup"
			rm -r backup_files -errorAction SilentlyContinue
			mkdir backup_files -errorAction SilentlyContinue | Out-Null
			docker cp "${container_name}:/flyt/userapps" backup_files
            docker cp "${container_name}:/flyt/flytos/flytcore/share/core_api/scripts" backup_files
			docker rm $container_name
		}
	}
}

$openBrowser = {
    sleep 30
    Start-Process "chrome.exe" "http://localhost/flytconsole"
    if ($? -ne "True"){
        Start-Process "microsoft-edge:http://localhost/flytconsole"
    }
}

$push_backup_files = {
    param($is_new_img,$scriptroot,$container_name)
    cd $scriptroot
    if ($is_new_img -eq "1")
    {
        while ($true){
            if ( docker ps | where {$_ -match $container_name} )
            {
                sleep 0.5
                docker cp backup_files/userapps ${container_name}:/flyt    
                if (Test-Path backup_files/scripts/lic_data.txt -PathType Leaf){
                    docker cp backup_files/scripts/lic_data.txt ${container_name}:/flyt/flytos/flytcore/share/core_api/scripts/lic_data.txt
                }    
                if (Test-Path backup_files/scripts/hwid -PathType Leaf){
                    docker cp backup_files/scripts/hwid ${container_name}:/flyt/flytos/flytcore/share/core_api/scripts/hwid
                }
                rm -r backup_files
                break
            }
            sleep 0.5
        }
    }
}

function start_docker {
    if ( docker ps | where {$_ -match $container_name} )
    {
        docker-compose stop
    }
    Write-Host("`nLaunching FlytSim now in a new window.`n`n") -ForegroundColor Green
    Start-Process powershell "docker-compose up"
    
    if ($? -ne "True"){
        Write-Host("`nError: Problem encountered. Could not start Flytsim session. Exiting ...") -ForegroundColor Red
        pause
        exit
    }
}

cd $PSScriptRoot
replaceip
is_docker_installed_and_running
is_xming_installed_and_running
close_ports
do_image_pull
Start-Job -scriptblock $openBrowser | Out-Null
Start-Job -scriptblock $push_backup_files -ArgumentList $Global:is_new_img,$PSScriptRoot,$container_name | Out-Null
start_docker

$host.enternestedprompt()