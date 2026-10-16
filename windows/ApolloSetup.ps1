<#
.SYNOPSIS
  Houston - setup window for Windows (and uninstall window with -Uninstall).
  Started by Setup.bat / Uninstall.bat. Uses WPF, which is built into Windows.

  The window only collects answers. The actual work (shortcuts, and a schedule on
  this PC when Houston isn't installed) is done by Install-ApolloSchedule.ps1, the
  same engine the text setup uses.
  Exit code 99 means the window could not be shown; the .bat then falls back
  to the text setup.
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
try {
  Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
} catch { exit 99 }

$Here       = $PSScriptRoot
$CommonPath = Join-Path $Here 'ApolloCommon.ps1'
$Engine     = Join-Path $Here 'Install-ApolloSchedule.ps1'
$PsExe      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$AppIcon    = Join-Path $Here 'icons\houston.ico'
. $CommonPath

# ============================================================================
#  Shared look
# ============================================================================
$Styles = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style x:Key="Primary" TargetType="Button">
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="Background" Value="#16150F"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Padding" Value="24,9"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#34322A"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Primary}">
    <Setter Property="Background" Value="#C7333A"/>
  </Style>
  <Style x:Key="Secondary" TargetType="Button">
    <Setter Property="Foreground" Value="#16150F"/>
    <Setter Property="Background" Value="White"/>
    <Setter Property="BorderBrush" Value="#DAD6CA"/>
    <Setter Property="Padding" Value="18,8"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#ECE9E1"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Link" TargetType="Button">
    <Setter Property="Foreground" Value="#16150F"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <ContentPresenter Margin="0,4"/>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Day" TargetType="ToggleButton">
    <Setter Property="Width" Value="38"/>
    <Setter Property="Height" Value="38"/>
    <Setter Property="Margin" Value="0,0,6,0"/>
    <Setter Property="Foreground" Value="#4A473F"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToggleButton">
          <Border x:Name="b" Background="#ECE9E1" CornerRadius="19">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="b" Property="Background" Value="#16150F"/>
              <Setter Property="Foreground" Value="White"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Choice" TargetType="RadioButton">
    <Setter Property="Margin" Value="0,0,10,10"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" Background="White" BorderBrush="#DAD6CA" BorderThickness="1.5" CornerRadius="10" Padding="14,12">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#8F8A7E"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="b" Property="BorderBrush" Value="#16150F"/>
              <Setter TargetName="b" Property="Background" Value="#ECE9E1"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Card" TargetType="Border">
    <Setter Property="Background" Value="White"/>
    <Setter Property="BorderBrush" Value="#DAD6CA"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="CornerRadius" Value="12"/>
    <Setter Property="Padding" Value="20,16"/>
    <Setter Property="Margin" Value="0,0,0,12"/>
  </Style>
  <Style x:Key="Field" TargetType="TextBox">
    <Setter Property="Padding" Value="8,7"/>
    <Setter Property="BorderBrush" Value="#DAD6CA"/>
    <Setter Property="FontSize" Value="15"/>
  </Style>
  <Style x:Key="Muted" TargetType="TextBlock">
    <Setter Property="Foreground" Value="#66625A"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>
  <Style x:Key="H" TargetType="TextBlock">
    <Setter Property="TextWrapping" Value="Wrap"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="15"/>
  </Style>
</ResourceDictionary>
'@

# The Houston mark (sidebar logo): graphite tile, H, flat orange orbit with a satellite
$Logo = @'
<Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="42" Height="42">
  <Canvas Width="100" Height="100">
    <Rectangle Width="100" Height="100" RadiusX="22.5" RadiusY="22.5" Fill="#0F100D" Stroke="#3A3A33" StrokeThickness="1"/>
    <Ellipse Canvas.Left="14" Canvas.Top="38" Width="72" Height="22" Stroke="#F7931A" StrokeThickness="3.5">
      <Ellipse.RenderTransform><RotateTransform Angle="-15" CenterX="36" CenterY="11"/></Ellipse.RenderTransform>
    </Ellipse>
    <Rectangle Canvas.Left="35" Canvas.Top="29" Width="10" Height="42" RadiusX="2" RadiusY="2" Fill="#EEEAE0"/>
    <Rectangle Canvas.Left="55" Canvas.Top="29" Width="10" Height="42" RadiusX="2" RadiusY="2" Fill="#EEEAE0"/>
    <Rectangle Canvas.Left="44" Canvas.Top="46" Width="12" Height="8" Fill="#EEEAE0"/>
    <Canvas>
      <Canvas.RenderTransform><RotateTransform Angle="-15" CenterX="50" CenterY="49"/></Canvas.RenderTransform>
      <Path Data="M 14,49 A 36,11 0 0 0 86,49" Stroke="#0F100D" StrokeThickness="6.5"/>
      <Path Data="M 14,49 A 36,11 0 0 0 86,49" Stroke="#F7931A" StrokeThickness="3.5"/>
      <Ellipse Canvas.Left="79.5" Canvas.Top="42.5" Width="13" Height="13" Fill="#0F100D"/>
      <Ellipse Canvas.Left="82" Canvas.Top="45" Width="8" Height="8" Fill="#EEEAE0"/>
    </Canvas>
  </Canvas>
</Viewbox>
'@

function New-Xaml([string]$xaml) {
  $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
  return [Windows.Markup.XamlReader]::Load($reader)
}

function Set-WindowLook($win) {
  $win.Resources.MergedDictionaries.Add((New-Xaml $Styles))
  if (Test-Path $AppIcon) { try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$AppIcon) } catch { } }
}

# ============================================================================
#  Background work, so the window never freezes
# ============================================================================
$script:Jobs = New-Object System.Collections.ArrayList
$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromMilliseconds(150)

# Run PowerShell code (with ApolloCommon.ps1 loaded) on a background runspace.
function Start-Background([string]$code, [object[]]$arguments, [scriptblock]$onDone) {
  $ps = [powershell]::Create()
  $common = $CommonPath -replace "'", "''"
  [void]$ps.AddScript("param(`$a, `$b)`n. '$common'`n$code")
  foreach ($x in $arguments) { [void]$ps.AddArgument($x) }
  [void]$script:Jobs.Add(@{ Kind = 'ps'; PS = $ps; Handle = $ps.BeginInvoke(); Done = $onDone })
  $script:Timer.Start()
}

# Run the setup engine as a separate, hidden PowerShell process.
function Start-Engine([string[]]$engineArgs, [scriptblock]$onDone) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PsExe
  $quoted = $engineArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Engine`" " + ($quoted -join ' ')
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  [void]$script:Jobs.Add(@{ Kind = 'proc'; Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync(); Done = $onDone })
  $script:Timer.Start()
}

$script:Timer.Add_Tick({
  foreach ($j in @($script:Jobs)) {
    if ($j.Kind -eq 'ps' -and $j.Handle.IsCompleted) {
      [void]$script:Jobs.Remove($j)
      $result = $null; $err = $null
      try { $result = $j.PS.EndInvoke($j.Handle) } catch { $err = $_.Exception.Message }
      $j.PS.Dispose()
      Invoke-Safe { & $j.Done $result $err }
    } elseif ($j.Kind -eq 'proc' -and $j.Proc.HasExited -and $j.Out.IsCompleted -and $j.Err.IsCompleted) {
      [void]$script:Jobs.Remove($j)
      $log = ($j.Out.Result + "`n" + $j.Err.Result).Trim()
      Invoke-Safe { & $j.Done $j.Proc.ExitCode $log }
    }
  }
  if (-not $script:Jobs.Count) { $script:Timer.Stop() }
})

function Invoke-Safe([scriptblock]$block) {
  try { & $block } catch {
    if ($script:ui -and $script:ui.Status) { $script:ui.Status.Text = "Something went wrong: $($_.Exception.Message)" }
    else { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Houston') | Out-Null }
  }
}

# ============================================================================
#  Uninstall window
# ============================================================================
if ($Uninstall) {
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Uninstall Houston from this PC" Width="540" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Background="#F6F4EE" FontFamily="Segoe UI" FontSize="14" Foreground="#16150F">
  <StackPanel Margin="30,26">
    <StackPanel Orientation="Horizontal">
      <ContentControl x:Name="LogoHost"/>
      <TextBlock Text="Remove Houston from this PC" FontSize="20" FontWeight="SemiBold" VerticalAlignment="Center" Margin="14,0,0,0"/>
    </StackPanel>
    <Border Style="{StaticResource Card}" Margin="0,20,0,0">
      <StackPanel>
        <TextBlock x:Name="Body" TextWrapping="Wrap" Text="This removes Houston's shortcuts (and any Apollo tasks in Task Scheduler) from this PC. Houston on your Apollo, its schedule, mining and settings are not changed."/>
        <CheckBox x:Name="DeleteBox" Margin="0,14,0,0" Content="Also delete the saved Apollo address and password from this PC"/>
      </StackPanel>
    </Border>
    <TextBlock x:Name="Status" Style="{StaticResource Muted}" Margin="2,0,0,10"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="CancelBtn" Content="Cancel" Style="{StaticResource Secondary}" Margin="0,0,10,0"/>
      <Button x:Name="GoBtn" Content="Uninstall" Style="{StaticResource Danger}"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
  try {
    $win = New-Xaml ($xaml -replace '\{StaticResource (\w+)\}', '{DynamicResource $1}')
    Set-WindowLook $win
  } catch { exit 99 }
  $script:ui = @{}
  foreach ($n in 'LogoHost', 'Body', 'DeleteBox', 'Status', 'CancelBtn', 'GoBtn') { $script:ui[$n] = $win.FindName($n) }
  $script:ui.LogoHost.Content = New-Xaml $Logo
  $script:ui.CancelBtn.Add_Click({ $win.Close() })
  $script:ui.GoBtn.Add_Click({ Invoke-Safe {
    if ($script:ui.GoBtn.Content -eq 'Close') { $win.Close(); return }
    $script:ui.GoBtn.IsEnabled = $false; $script:ui.CancelBtn.IsEnabled = $false; $script:ui.DeleteBox.IsEnabled = $false
    $script:ui.Status.Text = 'Removing...'
    $a = @('-Uninstall', '-Yes'); if ($script:ui.DeleteBox.IsChecked) { $a += '-DeleteSettings' }
    Start-Engine $a {
      param($code, $log)
      if ($code -eq 0) {
        $script:ui.Body.Text = 'Done. The shortcuts are gone. You can delete the Houston download folder now.'
        $script:ui.Status.Text = ''
      } else {
        $script:ui.Status.Text = "Uninstall failed:`n$log"
      }
      $script:ui.GoBtn.Content = 'Close'; $script:ui.GoBtn.Style = $win.FindResource('Primary'); $script:ui.GoBtn.IsEnabled = $true
    }
  } })
  [void]$win.ShowDialog()
  exit 0
}

# ============================================================================
#  Setup window
# ============================================================================
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Houston - Setup" Width="900" Height="700" MinWidth="780" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#F6F4EE" FontFamily="Segoe UI" FontSize="14" Foreground="#16150F">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="230"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Sidebar -->
    <Border Background="#0F100D">
      <DockPanel Margin="22,26,22,22">
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
          <ContentControl x:Name="LogoHost"/>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="Houston" Foreground="White" FontWeight="Bold" FontSize="18"/>
            <TextBlock Text="for FutureBit Apollo" Foreground="#9A968B"/>
          </StackPanel>
        </StackPanel>
        <TextBlock DockPanel.Dock="Bottom" Text="Unofficial community tool. Not affiliated with FutureBit." TextWrapping="Wrap" Foreground="#9A968B" FontSize="11"/>
        <StackPanel x:Name="Steps" Margin="0,40,0,0"/>
      </DockPanel>
    </Border>

    <!-- Content -->
    <Grid Grid.Column="1" Margin="36,30,36,24">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel>
        <TextBlock x:Name="PageTitle" FontSize="24" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <TextBlock x:Name="PageSub" Style="{StaticResource Muted}" Margin="0,4,0,0"/>
      </StackPanel>

      <ScrollViewer Grid.Row="1" Margin="0,18,0,12" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" x:Name="Scroller">
        <Grid>
          <!-- 1. Find -->
          <StackPanel x:Name="PageFind">
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Apollo address" Style="{StaticResource H}"/>
                <TextBlock Text="The address you open the Apollo dashboard at, for example 192.168.1.50." Style="{StaticResource Muted}" Margin="0,2,0,10"/>
                <DockPanel>
                  <Button x:Name="SearchBtn" DockPanel.Dock="Right" Content="Search my network" Style="{StaticResource Secondary}" Margin="10,0,0,0"/>
                  <TextBox x:Name="HostBox" Style="{StaticResource Field}"/>
                </DockPanel>
                <TextBlock x:Name="SearchInfo" Style="{StaticResource Muted}" Margin="0,10,0,0"/>
                <ListBox x:Name="FoundList" Margin="0,8,0,0" Visibility="Collapsed" BorderBrush="#DAD6CA" FontSize="15"/>
              </StackPanel>
            </Border>
            <TextBlock Style="{StaticResource Muted}" Margin="2,2,0,0" Text="Tip: give the Apollo a fixed address in your router (a DHCP reservation) so it never changes."/>
          </StackPanel>

          <!-- 2. Sign in -->
          <StackPanel x:Name="PageLogin" Visibility="Collapsed">
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Dashboard password" Style="{StaticResource H}"/>
                <TextBlock Text="The password you log in to the Apollo dashboard with. It is stored encrypted, readable only by your Windows account." Style="{StaticResource Muted}" Margin="0,2,0,10"/>
                <PasswordBox x:Name="PwBox" Padding="8,7" FontSize="15" BorderBrush="#DAD6CA"/>
              </StackPanel>
            </Border>
            <Border x:Name="LoginResult" Style="{StaticResource Card}" Background="#F0FDF4" BorderBrush="#BBF7D0" Visibility="Collapsed">
              <TextBlock x:Name="LoginResultText" TextWrapping="Wrap" Foreground="#166534"/>
            </Border>
          </StackPanel>

          <!-- 3. Houston + shortcuts -->
          <StackPanel x:Name="PageSchedule" Visibility="Collapsed">
            <Border x:Name="HoustonFound" Style="{StaticResource Card}" Background="#F0FDF4" BorderBrush="#BBF7D0">
              <DockPanel>
                <Button x:Name="OpenHouston" DockPanel.Dock="Right" Content="Open Houston" Style="{StaticResource Secondary}" VerticalAlignment="Center" Margin="12,0,0,0"/>
                <StackPanel>
                  <TextBlock x:Name="HoustonFoundTitle" Text="Houston is running on your Apollo" Style="{StaticResource H}" Foreground="#166534"/>
                  <TextBlock Text="Your schedule lives in Houston and runs on the Apollo itself, so this PC can be off. Any old Apollo tasks on this PC are removed." TextWrapping="Wrap" Foreground="#166534" Margin="0,2,0,0"/>
                </StackPanel>
              </DockPanel>
            </Border>
            <Border x:Name="HoustonMissing" Style="{StaticResource Card}" Background="#FBF6DD" BorderBrush="#E9D98A" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Houston isn't installed on this Apollo yet" Style="{StaticResource H}" Foreground="#6E5700"/>
                <TextBlock TextWrapping="Wrap" Foreground="#6E5700" Margin="0,2,0,8" Text="Houston is the app (phone and PC) and runs your schedule on the Apollo, so this PC doesn't have to stay on. To install it, run these two commands in PowerShell (the password is your dashboard password), then click Check again."/>
                <TextBox x:Name="HoustonCmds" IsReadOnly="True" FontFamily="Consolas" FontSize="12.5" TextWrapping="Wrap" Padding="8,6" BorderBrush="#E9D98A"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <Button x:Name="CopyCmds" Content="Copy commands" Style="{StaticResource Secondary}" Margin="0,0,10,0"/>
                  <Button x:Name="CheckHouston" Content="Check again" Style="{StaticResource Secondary}"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <TextBlock Text="Desktop shortcuts" Style="{StaticResource H}" Margin="0,6,0,8"/>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <CheckBox x:Name="ChkHouston" IsChecked="True" Margin="0,0,0,8"><TextBlock TextWrapping="Wrap"><Run FontWeight="SemiBold" Text="Houston"/><Run Foreground="#66625A" Text="  opens the app in its own window (Start menu too)"/></TextBlock></CheckBox>
                <CheckBox x:Name="ChkControl" IsChecked="True" Margin="0,0,0,8"><TextBlock TextWrapping="Wrap"><Run FontWeight="SemiBold" Text="Start, Stop, Status"/><Run Foreground="#66625A" Text="  one click, with a pop-up result"/></TextBlock></CheckBox>
                <CheckBox x:Name="ChkModes" IsChecked="True" Margin="0,0,0,8"><TextBlock TextWrapping="Wrap"><Run FontWeight="SemiBold" Text="Power modes"/><Run x:Name="ModesRun" Foreground="#66625A" Text="  Eco, Balanced, Turbo"/></TextBlock></CheckBox>
                <CheckBox x:Name="ChkNode" IsChecked="False"><TextBlock TextWrapping="Wrap"><Run FontWeight="SemiBold" Text="Start/Stop Bitcoin Node"/><Run Foreground="#66625A" Text="  most people leave the node running"/></TextBlock></CheckBox>
              </StackPanel>
            </Border>

            <Expander x:Name="PcSchedule" Header="Schedule on this PC instead (only without Houston)" Margin="2,4,0,0" Visibility="Collapsed">
            <StackPanel Margin="0,10,0,0">
            <TextBlock Text="Runs only while this PC is on and you're signed in. What should happen automatically?" Style="{StaticResource Muted}" Margin="0,0,0,10"/>
            <UniformGrid Columns="2">
              <RadioButton x:Name="OptMode" GroupName="sched" Style="{StaticResource Choice}">
                <StackPanel><TextBlock Text="Mine 24/7, faster at set times" FontWeight="SemiBold"/><TextBlock Text="A quiet mode most of the time, a faster one during set hours." Style="{StaticResource Muted}" FontSize="12.5"/></StackPanel>
              </RadioButton>
              <RadioButton x:Name="OptRun" GroupName="sched" Style="{StaticResource Choice}">
                <StackPanel><TextBlock Text="Mine only during set hours" FontWeight="SemiBold"/><TextBlock Text="Start and stop the miner on a schedule." Style="{StaticResource Muted}" FontSize="12.5"/></StackPanel>
              </RadioButton>
              <RadioButton x:Name="OptBoth" GroupName="sched" Style="{StaticResource Choice}">
                <StackPanel><TextBlock Text="Both" FontWeight="SemiBold"/><TextBlock Text="Mining hours, plus mode changes within them." Style="{StaticResource Muted}" FontSize="12.5"/></StackPanel>
              </RadioButton>
              <RadioButton x:Name="OptNone" GroupName="sched" Style="{StaticResource Choice}" IsChecked="True">
                <StackPanel><TextBlock Text="No schedule" FontWeight="SemiBold"/><TextBlock Text="Just the desktop shortcuts." Style="{StaticResource Muted}" FontSize="12.5"/></StackPanel>
              </RadioButton>
            </UniformGrid>

            <StackPanel x:Name="ModeSection" Margin="0,10,0,0">
              <TextBlock Text="Mode schedule" Style="{StaticResource H}" Margin="0,0,0,8"/>
              <Border Style="{StaticResource Card}">
                <WrapPanel>
                  <TextBlock Text="Normal mode, the rest of the time" VerticalAlignment="Center" Margin="0,0,12,0"/>
                  <ComboBox x:Name="BaseCombo" Width="170" Padding="8,6"/>
                  <ComboBox x:Name="BaseHr" Width="110" Padding="8,6" Margin="8,0,0,0" Visibility="Collapsed"/>
                </WrapPanel>
              </Border>
              <StackPanel x:Name="ModeRows"/>
              <Button x:Name="AddModeRow" Content="+ Add another time window" Style="{StaticResource Link}" HorizontalAlignment="Left"/>
            </StackPanel>

            <StackPanel x:Name="RunSection" Margin="0,14,0,0">
              <TextBlock Text="Mining hours (the miner is stopped outside these)" Style="{StaticResource H}" Margin="0,0,0,8"/>
              <StackPanel x:Name="RunRows"/>
              <Button x:Name="AddRunRow" Content="+ Add another time window" Style="{StaticResource Link}" HorizontalAlignment="Left"/>
            </StackPanel>
            </StackPanel>
            </Expander>
          </StackPanel>

          <!-- 4. Review -->
          <StackPanel x:Name="PageReview" Visibility="Collapsed">
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Your Apollo" Style="{StaticResource H}"/>
                <TextBlock x:Name="ReviewApollo" Style="{StaticResource Muted}" Margin="0,2,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Shortcuts and schedule" Style="{StaticResource H}"/>
                <TextBlock x:Name="ReviewSchedule" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="22"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Setup will" Style="{StaticResource H}"/>
                <TextBlock x:Name="ReviewActions" Style="{StaticResource Muted}" Margin="0,4,0,0" LineHeight="22"/>
              </StackPanel>
            </Border>
            <ProgressBar x:Name="Progress" Height="6" IsIndeterminate="True" Visibility="Collapsed" Foreground="#16150F" Background="#DAD6CA" BorderThickness="0"/>
          </StackPanel>

          <!-- 5. Done -->
          <StackPanel x:Name="PageDone" Visibility="Collapsed">
            <Border Style="{StaticResource Card}" Padding="24,22">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid Width="52" Height="52" VerticalAlignment="Top">
                  <Ellipse x:Name="DoneCircle" Fill="#1F8A4C"/>
                  <Path x:Name="DoneMark" Data="M15,27 L23,35 L38,18" Stroke="White" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                </Grid>
                <StackPanel Grid.Column="1" Margin="18,2,0,0">
                  <TextBlock x:Name="DoneTitle" FontSize="20" FontWeight="SemiBold" TextWrapping="Wrap"/>
                  <TextBlock x:Name="DoneText" TextWrapping="Wrap" Margin="0,6,0,0" LineHeight="22"/>
                </StackPanel>
              </Grid>
            </Border>
            <Button x:Name="DoneHouston" Content="Open Houston" Style="{StaticResource Primary}" HorizontalAlignment="Left" Margin="2,0,0,12" Visibility="Collapsed"/>
            <Expander Header="Details" Margin="2,0,0,0">
              <TextBox x:Name="LogBox" IsReadOnly="True" FontFamily="Consolas" FontSize="12" MaxHeight="220" Margin="0,8,0,0"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"/>
            </Expander>
          </StackPanel>
        </Grid>
      </ScrollViewer>

      <DockPanel Grid.Row="2">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BackBtn" Content="Back" Style="{StaticResource Secondary}" Margin="0,0,10,0"/>
          <Button x:Name="NextBtn" Content="Next" Style="{StaticResource Primary}"/>
        </StackPanel>
        <TextBlock x:Name="Status" VerticalAlignment="Center" Foreground="#C7333A" TextWrapping="Wrap" Margin="0,0,16,0"/>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
'@

try {
  # Styles are merged in after loading, so reference them dynamically
  $win = New-Xaml ($xaml -replace '\{StaticResource (\w+)\}', '{DynamicResource $1}')
  Set-WindowLook $win
} catch { exit 99 }

$script:ui = @{}
foreach ($n in 'LogoHost', 'Steps', 'PageTitle', 'PageSub', 'Scroller', 'PageFind', 'SearchBtn', 'HostBox', 'SearchInfo', 'FoundList',
               'PageLogin', 'PwBox', 'LoginResult', 'LoginResultText', 'PageSchedule', 'OptMode', 'OptRun', 'OptBoth', 'OptNone',
               'HoustonFound', 'HoustonFoundTitle', 'OpenHouston', 'HoustonMissing', 'HoustonCmds', 'CopyCmds', 'CheckHouston',
               'ChkHouston', 'ChkControl', 'ChkModes', 'ChkNode', 'ModesRun', 'PcSchedule', 'DoneHouston',
               'ModeSection', 'BaseCombo', 'BaseHr', 'ModeRows', 'AddModeRow', 'RunSection', 'RunRows', 'AddRunRow',
               'PageReview', 'ReviewApollo', 'ReviewSchedule', 'ReviewActions', 'Progress',
               'PageDone', 'DoneCircle', 'DoneMark', 'DoneTitle', 'DoneText', 'LogBox', 'BackBtn', 'NextBtn', 'Status') {
  $script:ui[$n] = $win.FindName($n)
}
$ui = $script:ui
$ui.LogoHost.Content = New-Xaml $Logo

# ---------------------------------------------------------------- state
$script:page    = 0
$script:busy    = $false
$script:apollo  = ''
$script:isIII   = $false
$script:login   = $null
$script:modeRows = New-Object System.Collections.ArrayList
$script:runRows  = New-Object System.Collections.ArrayList
$script:scheduleBuiltFor = $null
$script:houston = $null

$Pages  = @($ui.PageFind, $ui.PageLogin, $ui.PageSchedule, $ui.PageReview, $ui.PageDone)
$Titles = @(
  @('Find your Apollo', 'Setup will find it on your network, or you can type its address.'),
  @('Sign in', 'Setup checks the password with your Apollo before saving anything.'),
  @('Houston and shortcuts', 'Connect to Houston on your Apollo and pick the shortcuts you want.'),
  @('Review', 'Nothing has changed on this PC yet. Click Install to finish.'),
  @('', '')
)
$StepNames = @('Find your Apollo', 'Sign in', 'Houston', 'Install')

# Times every 15 minutes, as shown in the time boxes
$TimeChoices = foreach ($m in 0..95) { ([datetime]::Today.AddMinutes($m * 15)).ToString('h:mm tt', [Globalization.CultureInfo]::InvariantCulture) }

# ---------------------------------------------------------------- helpers
function Brush([string]$hex) { return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex) }

function Update-Steps {
  $ui.Steps.Children.Clear()
  for ($i = 0; $i -lt $StepNames.Count; $i++) {
    $current = ($i -eq [Math]::Min($script:page, 3)) -and $script:page -lt 4
    $done = $i -lt $script:page -or $script:page -eq 4
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,18'
    $dot = New-Object System.Windows.Controls.Grid
    $dot.Width = 28; $dot.Height = 28
    $circle = New-Object System.Windows.Shapes.Ellipse
    $circle.Fill = if ($current) { Brush '#EEEAE0' } elseif ($done) { Brush '#2B2B26' } else { Brush '#151612' }
    $circle.Stroke = if ($current -or $done) { $null } else { Brush '#3A3A33' }
    [void]$dot.Children.Add($circle)
    if ($done -and -not $current) {
      $tick = New-Object System.Windows.Shapes.Path
      $tick.Data = [System.Windows.Media.Geometry]::Parse('M8.5,14.5 L12.5,18.5 L19.5,10.5')
      $tick.Stroke = Brush '#8BDDAE'; $tick.StrokeThickness = 2.4
      $tick.StrokeStartLineCap = 'Round'; $tick.StrokeEndLineCap = 'Round'; $tick.StrokeLineJoin = 'Round'
      [void]$dot.Children.Add($tick)
    } else {
      $num = New-Object System.Windows.Controls.TextBlock
      $num.Text = "$($i + 1)"; $num.FontSize = 13
      $num.FontWeight = 'Bold'; $num.HorizontalAlignment = 'Center'; $num.VerticalAlignment = 'Center'
      $num.Foreground = if ($current) { Brush '#0F100D' } else { Brush '#9A968B' }
      [void]$dot.Children.Add($num)
    }
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $StepNames[$i]; $label.Margin = '12,0,0,0'; $label.VerticalAlignment = 'Center'
    $label.Foreground = if ($current) { Brush '#FFFFFF' } elseif ($done) { Brush '#C9C4B8' } else { Brush '#9A968B' }
    if ($current) { $label.FontWeight = 'SemiBold' }
    [void]$row.Children.Add($dot); [void]$row.Children.Add($label)
    [void]$ui.Steps.Children.Add($row)
  }
}

function Show-Page([int]$n) {
  $script:page = $n
  for ($i = 0; $i -lt $Pages.Count; $i++) { $Pages[$i].Visibility = if ($i -eq $n) { 'Visible' } else { 'Collapsed' } }
  $ui.PageTitle.Text = $Titles[$n][0]; $ui.PageSub.Text = $Titles[$n][1]
  $ui.PageTitle.Visibility = if ($n -eq 4) { 'Collapsed' } else { 'Visible' }
  $ui.PageSub.Visibility = $ui.PageTitle.Visibility
  $ui.Status.Text = ''
  $ui.BackBtn.Visibility = if ($n -eq 0 -or $n -eq 4) { 'Hidden' } else { 'Visible' }
  $ui.NextBtn.Content = switch ($n) { 3 { 'Install' } 4 { 'Close' } default { 'Next' } }
  $ui.Scroller.ScrollToTop()
  Update-Steps
  if ($n -eq 0) { $ui.HostBox.Focus() | Out-Null }
  if ($n -eq 1) { $ui.PwBox.Focus() | Out-Null }
}

function Set-Busy([bool]$b, [string]$msg) {
  $script:busy = $b
  $ui.NextBtn.IsEnabled = -not $b; $ui.BackBtn.IsEnabled = -not $b; $ui.SearchBtn.IsEnabled = -not $b
  $ui.Status.Foreground = Brush '#66625A'
  $ui.Status.Text = $msg
  $win.Cursor = if ($b) { [System.Windows.Input.Cursors]::Wait } else { $null }
}

function Show-Error([string]$msg) {
  $ui.Status.Foreground = Brush '#C7333A'
  $ui.Status.Text = $msg
}

function New-Combo([string[]]$labels, [string[]]$tags, [int]$width) {
  $c = New-Object System.Windows.Controls.ComboBox
  $c.Width = $width; $c.Padding = '8,6'; $c.Margin = '0,0,8,0'; $c.VerticalAlignment = 'Center'
  for ($i = 0; $i -lt $labels.Count; $i++) {
    $it = New-Object System.Windows.Controls.ComboBoxItem
    $it.Content = $labels[$i]; $it.Tag = $tags[$i]
    [void]$c.Items.Add($it)
  }
  return $c
}

function Select-Tag($combo, [string]$tag) {
  foreach ($it in $combo.Items) { if ("$($it.Tag)" -eq $tag) { $combo.SelectedItem = $it; return } }
  if ($combo.Items.Count) { $combo.SelectedIndex = 0 }
}

function New-TimeBox([string]$value, [switch]$AllowNever) {
  $c = New-Object System.Windows.Controls.ComboBox
  $c.IsEditable = $true; $c.Width = 120; $c.Padding = '8,6'; $c.Margin = '0,0,8,0'; $c.VerticalAlignment = 'Center'
  $c.MaxDropDownHeight = 260
  if ($AllowNever) { [void]$c.Items.Add('Never') }
  foreach ($t in $TimeChoices) { [void]$c.Items.Add($t) }
  $c.Text = $value
  return $c
}

function New-HrCombo {
  $labels = 5..20 | ForEach-Object { "$_ TH/s" }
  $tags   = 5..20 | ForEach-Object { "$_" }
  $c = New-Combo $labels $tags 100
  Select-Tag $c '16'
  $c.Visibility = 'Collapsed'
  return $c
}

function Get-ModeChoices([bool]$base) {
  if ($base) {
    if ($script:isIII) { return @(@('Super Eco', 'super_eco'), @('Eco', 'eco'), @('Balanced', 'balanced'), @('Custom target', 'custom')) }
    return @(@('Eco', 'eco'), @('Balanced', 'balanced'))
  }
  if ($script:isIII) { return @(@('Eco', 'eco'), @('Balanced', 'balanced'), @('Turbo', 'turbo'), @('Custom target', 'custom')) }
  return @(@('Balanced', 'balanced'), @('Turbo', 'turbo'))
}

function Get-Label([string]$text, [string]$margin) {
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $text; $t.VerticalAlignment = 'Center'; $t.Margin = $margin; $t.Foreground = Brush '#4A473F'
  return $t
}

# One schedule window: day toggles, times and (for mode windows) a mode
function Add-Row([string]$type) {
  $list  = if ($type -eq 'mode') { $script:modeRows } else { $script:runRows }
  $panel = if ($type -eq 'mode') { $ui.ModeRows } else { $ui.RunRows }

  $card = New-Object System.Windows.Controls.Border
  $card.Style = $win.FindResource('Card')
  $stack = New-Object System.Windows.Controls.StackPanel
  $card.Child = $stack

  # days + remove
  $top = New-Object System.Windows.Controls.DockPanel
  $remove = New-Object System.Windows.Controls.Button
  $remove.Content = 'Remove'; $remove.Style = $win.FindResource('Link'); [System.Windows.Controls.DockPanel]::SetDock($remove, 'Right')
  $remove.VerticalAlignment = 'Center'
  [void]$top.Children.Add($remove)
  $days = New-Object System.Windows.Controls.StackPanel
  $days.Orientation = 'Horizontal'
  $toggles = @()
  $letters = 'M', 'T', 'W', 'T', 'F', 'S', 'S'
  for ($i = 0; $i -lt 7; $i++) {
    $tb = New-Object System.Windows.Controls.Primitives.ToggleButton
    $tb.Style = $win.FindResource('Day'); $tb.Content = $letters[$i]; $tb.Tag = $WeekDays[$i]; $tb.ToolTip = $WeekDays[$i]
    $tb.IsChecked = $i -lt 5
    [void]$days.Children.Add($tb); $toggles += $tb
  }
  [void]$top.Children.Add($days)
  [void]$stack.Children.Add($top)

  # times (+ mode)
  $line = New-Object System.Windows.Controls.WrapPanel
  $line.Margin = '0,12,0,0'
  $row = @{ Type = $type; Card = $card; Toggles = $toggles }
  if ($type -eq 'mode') {
    [void]$line.Children.Add((Get-Label 'From' '0,0,8,0'))
    $row.On = New-TimeBox '9:00 AM'; [void]$line.Children.Add($row.On)
    [void]$line.Children.Add((Get-Label 'to' '0,0,8,0'))
    $row.Off = New-TimeBox '5:00 PM'; [void]$line.Children.Add($row.Off)
    [void]$line.Children.Add((Get-Label 'use' '6,0,8,0'))
    $choices = Get-ModeChoices $false
    $row.Mode = New-Combo ($choices | ForEach-Object { $_[0] }) ($choices | ForEach-Object { $_[1] }) 150
    $row.Hr = New-HrCombo
    $row.Mode.Tag = $row.Hr
    $row.Mode.Add_SelectionChanged({ param($s, $e) $s.Tag.Visibility = if ("$($s.SelectedItem.Tag)" -eq 'custom') { 'Visible' } else { 'Collapsed' } })
    Select-Tag $row.Mode 'turbo'
    [void]$line.Children.Add($row.Mode); [void]$line.Children.Add($row.Hr)
  } else {
    [void]$line.Children.Add((Get-Label 'Start mining at' '0,0,8,0'))
    $row.On = New-TimeBox '9:00 AM'; [void]$line.Children.Add($row.On)
    [void]$line.Children.Add((Get-Label 'stop at' '4,0,8,0'))
    $row.Off = New-TimeBox '5:00 PM' -AllowNever; [void]$line.Children.Add($row.Off)
  }
  [void]$stack.Children.Add($line)

  $remove.Tag = $row
  $remove.Add_Click({ param($s, $e) Invoke-Safe {
    $r = $s.Tag
    $l = if ($r.Type -eq 'mode') { $script:modeRows } else { $script:runRows }
    $p = if ($r.Type -eq 'mode') { $ui.ModeRows } else { $ui.RunRows }
    [void]$l.Remove($r); [void]$p.Children.Remove($r.Card)
    Update-RemoveButtons
  } })
  $row.Remove = $remove
  [void]$list.Add($row); [void]$panel.Children.Add($card)
  Update-RemoveButtons
}

function Update-RemoveButtons {
  foreach ($r in $script:modeRows) { $r.Remove.Visibility = if ($script:modeRows.Count -gt 1) { 'Visible' } else { 'Collapsed' } }
  foreach ($r in $script:runRows)  { $r.Remove.Visibility = if ($script:runRows.Count -gt 1) { 'Visible' } else { 'Collapsed' } }
}

function Update-Sections {
  $ui.ModeSection.Visibility = if ($ui.OptMode.IsChecked -or $ui.OptBoth.IsChecked) { 'Visible' } else { 'Collapsed' }
  $ui.RunSection.Visibility  = if ($ui.OptRun.IsChecked -or $ui.OptBoth.IsChecked) { 'Visible' } else { 'Collapsed' }
}

# (Re)build the schedule controls for the detected model
function Initialize-Schedule {
  if ($script:scheduleBuiltFor -eq $script:isIII) { return }
  $script:scheduleBuiltFor = $script:isIII
  $choices = Get-ModeChoices $true
  $ui.BaseCombo.Items.Clear(); $ui.BaseHr.Items.Clear()
  foreach ($c in $choices) { $it = New-Object System.Windows.Controls.ComboBoxItem; $it.Content = $c[0]; $it.Tag = $c[1]; [void]$ui.BaseCombo.Items.Add($it) }
  foreach ($h in 5..20) { $it = New-Object System.Windows.Controls.ComboBoxItem; $it.Content = "$h TH/s"; $it.Tag = "$h"; [void]$ui.BaseHr.Items.Add($it) }
  Select-Tag $ui.BaseHr '12'
  Select-Tag $ui.BaseCombo 'eco'
  $script:modeRows.Clear(); $ui.ModeRows.Children.Clear()
  $script:runRows.Clear();  $ui.RunRows.Children.Clear()
  Add-Row 'mode'; Add-Row 'run'
  Update-Sections
}

function Get-Token($combo, $hrCombo) {
  $t = "$($combo.SelectedItem.Tag)"
  if ($t -eq 'custom') { return "custom:$($hrCombo.SelectedItem.Tag)" }
  return $t
}

function Read-Time($box, [string]$what, [switch]$AllowNever) {
  $t = "$($box.Text)".Trim()
  if ($AllowNever -and ($t -eq '' -or $t -match '^never$')) { return $null }
  try { return ConvertTo-Time $t } catch { throw "Check the $what time: '$t'. Use a time like 9:30 AM." }
}

# Collect and check the schedule. Returns @{ Base; Windows = @(...) } or throws.
function Get-Schedule {
  $result = @{ Base = (Get-Token $ui.BaseCombo $ui.BaseHr); Windows = @() }
  if ($script:houston -or $ui.OptNone.IsChecked) { return $result }   # with Houston, the schedule lives there
  $n = 0
  if ($ui.OptRun.IsChecked -or $ui.OptBoth.IsChecked) {
    foreach ($r in $script:runRows) {
      $n++
      $d = @($r.Toggles | Where-Object { $_.IsChecked } | ForEach-Object { "$($_.Tag)" })
      if (-not $d.Count) { throw "Pick at least one day for mining window $n." }
      $result.Windows += @{ type = 'run'; days = $d; on = (Read-Time $r.On 'start'); off = (Read-Time $r.Off 'stop' -AllowNever) }
    }
  }
  $n = 0
  if ($ui.OptMode.IsChecked -or $ui.OptBoth.IsChecked) {
    foreach ($r in $script:modeRows) {
      $n++
      $d = @($r.Toggles | Where-Object { $_.IsChecked } | ForEach-Object { "$($_.Tag)" })
      if (-not $d.Count) { throw "Pick at least one day for time window $n." }
      $tok = Get-Token $r.Mode $r.Hr
      if ($tok -eq $result.Base) { throw "Time window $n uses $(Get-ModeLabel $tok), the same as the normal mode. Pick a different one." }
      $result.Windows += @{ type = 'mode'; days = $d; on = (Read-Time $r.On 'start'); off = (Read-Time $r.Off 'end'); mode = $tok }
    }
  }
  return $result
}

function Format-Time([datetime]$t) { return $t.ToString('h:mm tt', [Globalization.CultureInfo]::InvariantCulture) }

function Format-Schedule($s) {
  if ($script:houston) { return "Schedule: in Houston (open it and use the Schedule tab). Any old Apollo tasks on this PC are removed." }
  if (-not $s.Windows.Count) { return 'No schedule on this PC (any previous Apollo tasks are removed). Install Houston any time for a schedule that runs on the Apollo.' }
  $lines = foreach ($w in $s.Windows) {
    $days = Format-Days $w.days
    $on = Format-Time $w.on
    $next = if ($w.off -and $w.off.TimeOfDay -le $w.on.TimeOfDay) { ' (next day)' } else { '' }
    if ($w.type -eq 'run') {
      if ($w.off) { "$days  -  mine $on to $(Format-Time $w.off)$next" } else { "$days  -  start mining at $on (no automatic stop)" }
    } else {
      "$days  -  $(Get-ModeLabel $w.mode) from $on to $(Format-Time $w.off)$next, $(Get-ModeLabel $s.Base) otherwise"
    }
  }
  return ($lines -join "`n")
}

# ---------------------------------------------------------------- Houston page
function Update-HoustonPage {
  $found = [bool]$script:houston
  $ui.HoustonFound.Visibility = if ($found) { 'Visible' } else { 'Collapsed' }
  $ui.HoustonMissing.Visibility = if ($found) { 'Collapsed' } else { 'Visible' }
  $ui.PcSchedule.Visibility = if ($found) { 'Collapsed' } else { 'Visible' }
  $ui.ChkHouston.IsEnabled = $found
  if (-not $found) { $ui.ChkHouston.IsChecked = $false }
  if ($found) { $ui.HoustonFoundTitle.Text = "Houston $($script:houston.Version) is running on your Apollo" }
  $ui.HoustonCmds.Text = (Get-HoustonInstallCommands $script:apollo) -join "`r`n"
  $ui.ModesRun.Text = if ($script:isIII) { '  Super Eco, Eco, Balanced, Turbo' } else { '  Eco, Balanced, Turbo' }
}

function Get-ShortcutGroups {
  $g = @()
  if ($ui.ChkHouston.IsChecked -and $script:houston) { $g += 'houston' }
  if ($ui.ChkControl.IsChecked) { $g += 'control' }
  if ($ui.ChkModes.IsChecked) { $g += 'modes' }
  if ($ui.ChkNode.IsChecked) { $g += 'node' }
  return $g
}

function Start-HoustonCheck {
  Set-Busy $true 'Looking for Houston...'
  Start-Background 'Get-Houston $a' @($script:apollo) {
    param($result, $err)
    Set-Busy $false ''
    $h = if ($result -and $result.Count) { $result[0] } else { $null }
    if ($h -is [psobject]) { $h = $h.psobject.BaseObject }
    $script:houston = $h
    if ($h) { $ui.ChkHouston.IsChecked = $true }
    Update-HoustonPage
    if (-not $h) { Show-Error "Houston still isn't answering at http://$($script:apollo):8088. Check that the installer finished." }
  }
}

# ---------------------------------------------------------------- page actions
function Start-Search {
  Set-Busy $true 'Searching your network (a few seconds)...'
  $ui.SearchInfo.Text = ''
  $ui.FoundList.Items.Clear(); $ui.FoundList.Visibility = 'Collapsed'
  Start-Background 'Find-Apollo' @() {
    param($result, $err)
    Set-Busy $false ''
    $found = @($result | ForEach-Object { "$_" } | Where-Object { $_ })
    if ($found.Count -eq 0) {
      $ui.SearchInfo.Text = "No Apollo found on this network. Type its address instead (the one you open the dashboard at)."
    } elseif ($found.Count -eq 1) {
      $ui.HostBox.Text = $found[0]
      $ui.SearchInfo.Text = "Found an Apollo at $($found[0])."
    } else {
      $ui.SearchInfo.Text = 'Found more than one Apollo. Pick one:'
      foreach ($f in $found) { [void]$ui.FoundList.Items.Add($f) }
      $ui.FoundList.Visibility = 'Visible'
    }
  }
}

function Start-Login {
  $pw = $ui.PwBox.Password
  if (-not $pw) { Show-Error 'Enter the dashboard password.'; return }
  $ui.LoginResult.Visibility = 'Collapsed'
  Set-Busy $true "Signing in to $($script:apollo)..."
  Start-Background 'Test-ApolloLogin $a $b' @($script:apollo, $pw) {
    param($result, $err)
    Set-Busy $false ''
    $r = if ($result -and $result.Count) { $result[0] } else { $null }
    if ($r -is [psobject]) { $r = $r.psobject.BaseObject }
    if ($err -or -not $r) { Show-Error "Couldn't check the password: $err"; return }
    if (-not $r.Ok) { Show-Error $r.Error; return }
    $script:login = $r
    $script:houston = $r.Houston
    if ($script:houston -is [psobject]) { $script:houston = $script:houston.psobject.BaseObject }
    $script:isIII = $r.Model -eq 'apollo-iii'
    $model = if ($script:isIII) { 'Apollo III' } else { 'Apollo II' }
    $mode = if ($r.Mode) { ", $(Get-ModeLabel $r.Mode) mode" } else { '' }
    $ui.LoginResultText.Text = "Connected to your $model at $($script:apollo): miner $($r.Status)$mode."
    $ui.LoginResult.Visibility = 'Visible'
    Initialize-Schedule
    if ($script:houston) { $ui.ChkHouston.IsChecked = $true }
    Update-HoustonPage
    Show-Page 2
  }
}

function Show-Review {
  try { $script:schedule = Get-Schedule } catch { Show-Error $_.Exception.Message; return }
  $model = if ($script:isIII) { 'Apollo III' } else { 'Apollo II' }
  $hv = if ($script:houston) { ", Houston $($script:houston.Version)" } else { ', no Houston yet' }
  $ui.ReviewApollo.Text = "$model at $($script:apollo)$hv"
  $extra = if ($script:isIII) { 'Super Eco, ' } else { '' }
  $names = @()
  $g = Get-ShortcutGroups
  if ($g -contains 'houston') { $names += 'Houston' }
  if ($g -contains 'control') { $names += 'Start, Stop, Status' }
  if ($g -contains 'modes') { $names += "${extra}Eco, Balanced, Turbo" }
  if ($g -contains 'node') { $names += 'Start/Stop Bitcoin Node' }
  $sc = if ($names.Count) { 'Shortcuts: ' + ($names -join ', ') } else { 'No shortcuts' }
  $ui.ReviewSchedule.Text = "$sc`n" + (Format-Schedule $script:schedule)
  $ui.ReviewActions.Text = @(
    '- Save the password, encrypted for your Windows account (the shortcuts use it)',
    '- Replace any Houston / Apollo shortcuts from before',
    $(if ($script:houston -or -not $script:schedule.Windows.Count) { '- Remove old Apollo tasks from Task Scheduler' } else { '- Create the scheduled tasks above (replacing any from before)' }),
    '- Lock the scripts folder so only your account can change it'
  ) -join "`n"
  Show-Page 3
}

function Start-Install {
  Set-Busy $true 'Setting up (about 10 seconds)...'
  $ui.Progress.Visibility = 'Visible'
  Save-ApolloPassword $ui.PwBox.SecurePassword
  $json = @{
    base    = $script:schedule.Base
    windows = @($script:schedule.Windows | ForEach-Object {
      @{ type = $_.type; days = $_.days; on = $_.on.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture); off = if ($_.off) { $_.off.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) } else { $null }; mode = $_.mode }
    })
  } | ConvertTo-Json -Depth 5
  $script:scheduleFile = Join-Path $env:TEMP "apollo-schedule-$PID.json"
  Set-Content -Path $script:scheduleFile -Value $json -Encoding UTF8
  $groups = @(Get-ShortcutGroups)
  $sc = if ($groups.Count) { $groups -join ',' } else { 'none' }
  Start-Engine @('-ApolloHost', $script:apollo, '-PasswordReady', '-Yes', '-Shortcuts', $sc, '-ScheduleFile', $script:scheduleFile) {
    param($code, $log)
    if ($script:scheduleFile) { Remove-Item -LiteralPath $script:scheduleFile -ErrorAction SilentlyContinue }
    $ui.Progress.Visibility = 'Collapsed'
    Set-Busy $false ''
    $ui.LogBox.Text = $log
    if ($code -eq 0) {
      $ui.DoneCircle.Fill = Brush '#1F8A4C'; $ui.DoneMark.Data = [System.Windows.Media.Geometry]::Parse('M15,27 L23,35 L38,18')
      $ui.DoneTitle.Text = "You're all set"
      $n = $script:schedule.Windows.Count
      $sched = if ($script:houston) { "Set your schedule in Houston ($($script:houston.Url)): the Apollo runs it by itself. Houston also works on your phone, and away from home through Tailscale." }
               elseif ($n) { 'Your schedule is saved in Task Scheduler (folder "Apollo Miner"). It runs while you are signed in to Windows; a locked screen is fine.' }
               else { 'No schedule was set. Install Houston on the Apollo for one that runs even when this PC is off.' }
      $sc = if ((Get-ShortcutGroups).Count) { 'Your desktop shortcuts are ready.' } else { 'No shortcuts were added.' }
      $ui.DoneText.Text = "$sc`n$sched`n`nRun Setup again any time to change the shortcuts."
      $ui.DoneHouston.Visibility = if ($script:houston) { 'Visible' } else { 'Collapsed' }
    } else {
      $ui.DoneCircle.Fill = Brush '#C7333A'; $ui.DoneMark.Data = [System.Windows.Media.Geometry]::Parse('M18,18 L34,34 M34,18 L18,34')
      $ui.DoneTitle.Text = 'Setup did not finish'
      $last = ($log -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
      $ui.DoneText.Text = "$last`n`nOpen Details below for the full log. Nothing on your Apollo was changed."
    }
    Show-Page 4
    if ($code -ne 0) { $ui.BackBtn.Visibility = 'Visible' }
  }
}

# ---------------------------------------------------------------- wiring
$ui.SearchBtn.Add_Click({ Invoke-Safe { Start-Search } })
$ui.OpenHouston.Add_Click({ Invoke-Safe { if ($script:houston) { Start-Process $script:houston.Url } } })
$ui.DoneHouston.Add_Click({ Invoke-Safe { if ($script:houston) { Start-Process $script:houston.Url } } })
$ui.CheckHouston.Add_Click({ Invoke-Safe { Start-HoustonCheck } })
$ui.CopyCmds.Add_Click({ Invoke-Safe { [System.Windows.Clipboard]::SetText($ui.HoustonCmds.Text); $ui.Status.Foreground = Brush '#1F8A4C'; $ui.Status.Text = 'Copied. Paste them into PowerShell, one at a time.' } })
$ui.FoundList.Add_SelectionChanged({ Invoke-Safe { if ($ui.FoundList.SelectedItem) { $ui.HostBox.Text = "$($ui.FoundList.SelectedItem)" } } })
$ui.AddModeRow.Add_Click({ Invoke-Safe { Add-Row 'mode' } })
$ui.AddRunRow.Add_Click({ Invoke-Safe { Add-Row 'run' } })
foreach ($o in $ui.OptMode, $ui.OptRun, $ui.OptBoth, $ui.OptNone) { $o.Add_Checked({ Invoke-Safe { Update-Sections } }) }
$ui.BaseCombo.Add_SelectionChanged({ Invoke-Safe { $ui.BaseHr.Visibility = if ("$($ui.BaseCombo.SelectedItem.Tag)" -eq 'custom') { 'Visible' } else { 'Collapsed' } } })
$ui.HostBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $ui.NextBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } })
$ui.PwBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $ui.NextBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } })

$ui.BackBtn.Add_Click({ Invoke-Safe {
  if ($script:busy) { return }
  if ($script:page -eq 4) { Show-Page 3 } elseif ($script:page -gt 0) { Show-Page ($script:page - 1) }
} })

$ui.NextBtn.Add_Click({ Invoke-Safe {
  if ($script:busy) { return }
  switch ($script:page) {
    0 {
      $h = "$($ui.HostBox.Text)".Trim() -replace '^https?://', '' -replace '[:/].*$', ''
      if (-not $h) { Show-Error 'Type the Apollo address, or click "Search my network".'; return }
      if ($h -notmatch '^[A-Za-z0-9.\-]+$') { Show-Error "'$h' doesn't look like an address. Example: 192.168.1.50"; return }
      if ($h -ne $script:apollo) { $script:login = $null; $ui.LoginResult.Visibility = 'Collapsed' }
      $script:apollo = $h
      Show-Page 1
    }
    1 { Start-Login }
    2 { Show-Review }
    3 { Start-Install }
    4 { $win.Close() }
  }
} })

# Prefill the address saved by an earlier setup
$savedHost = Join-Path $ApolloDataDir 'host.txt'
if (Test-Path $savedHost) { $ui.HostBox.Text = (Get-Content $savedHost -TotalCount 1).Trim(); $ui.SearchInfo.Text = 'Using the address from your last setup. Change it if your Apollo moved.' }

Show-Page 0
[void]$win.ShowDialog()
exit 0
