<#
.SYNOPSIS
    Remote App Uninstaller v1.0 — WPF GUI to inventory and uninstall applications
    on the local computer or a remote Windows computer.

.DESCRIPTION
    Remote App Uninstaller is a self-contained PowerShell WPF application that
    provides a modern graphical interface for managing installed applications
    across Windows machines.

    Core capabilities:

      - Automatic local inventory on startup (registry-based, both 64-bit and
        32-bit HKLM Uninstall views). The sidebar badge shows "This PC".
      - Remote target support: type a computer name or IP in the sidebar,
        press Enter (or click Load). The badge switches to "Remote".
        Connectivity is tested via ICMP ping before WinRM access.
      - Live Remote PC card: displays connectivity status (Connected/Offline),
        device name, IP address, logged-on user, and OS version.
      - Stats dashboard: Total apps, MSI count, EXE/Other count, and
        Selected count — updated on every selection change.
      - Real-time search with case-insensitive regex filtering across
        Name, Publisher, and Version.
      - Details pane: select an app to see Publisher, Version, InstallDate,
        UninstallString, Product Code, Architecture, Scope, Registry Key,
        and more. Context-menu or Ctrl+C to copy fields/rows.
      - Silent uninstall engine: auto-detects installer type (MSI, Inno,
        NSIS, Wise, InstallShield, generic EXE) and appends the correct
        silent switches (/quiet, /VERYSILENT, /S, etc.). Uninstall runs in
        a background Start-Job so the UI stays responsive; live output
        streams to the Message Center and a summary dialog appears on finish.
      - WinGet fallback: if the traditional uninstall fails, winget uninstall
        --silent is attempted automatically.
      - Post-uninstall cleanup: removes leftover registry entries, Program
        Files folders, Start Menu shortcuts, and AppData remnants.
      - CSV export: saves the currently filtered app list via a SaveFileDialog.

.PARAMETER None
    This script takes no command-line parameters. All interaction is performed
    through the WPF graphical user interface.

.EXAMPLE
    .\RemoteAppUninstaller.ps1

    Launches the GUI. The local machine is inventoried automatically on startup.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\RemoteAppManager-v1.0.ps1

    Bypasses the PowerShell execution policy to run the script.

.EXAMPLE
    # To target a remote computer:
    # 1. Launch the script.
    # 2. Type the remote computer name in the sidebar.
    # 3. Press Enter or click "Load Applications".

.INPUTS
    None. The script does not accept pipeline input.

.OUTPUTS
    None. All output is displayed in the WPF window and Message Center.

    Log levels (color-coded in the Message Center):
      INFO      — general operations (grey-blue)
      DETAIL    — workflow and connectivity details (light blue)
      RESULT    — success results (blue)
      WARN      — non-fatal warnings (yellow)
      ERROR     — failures (red)
      SUMMARY   — uninstall job summaries (green)

.NOTES
    ===========================================================================
    Requirements
    ===========================================================================
      - Windows PowerShell 5.1 or newer with WPF (.NET Framework).
      - For remote targets: WinRM enabled on the target machine
        (winrm quickconfig), the Windows Remote Management firewall rule
        open, and administrative rights on the target.
      - Workgroup targets may require TrustedHosts configuration or CredSSP.

    ===========================================================================
    Registry Touchpoints
    ===========================================================================
      HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
      HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall

    ===========================================================================
    File System Paths (cleanup phase)
    ===========================================================================
      C:\Program Files
      C:\Program Files (x86)
      C:\ProgramData\Microsoft\Windows\Start Menu\Programs
      C:\Users\*\AppData

    ===========================================================================
    Script Structure (regions in file order)
    ===========================================================================
      01. ASSEMBLIES & GLOBALS
      02. XAML — MAIN WINDOW (Part 1 / Part 2)
      03. XAML LOADER (SAFE)
      04. CONTROL BINDING (SAFE)
      05. TARGET HELPERS
      06. FOOTER LINK (OPTIONAL)
      07. SESSION INFO (SIDEBAR)
      08. UI INVOKE HELPERS
      09. LOGGER (Update-Output)
      10. LAST ACTION (OPTIONAL)
      11. STATS (CARDS)
      12. DETAILS PANES
      13. COLLECTION VIEW + FILTER
      14. GET-INSTALLEDAPPS
      15. CONFIRMATION DIALOG
      16. UNINSTALL SCRIPTBLOCK
      17. JOB POLLING (DispatcherTimer)
      18. BUTTON HANDLERS
      19. UI EVENTS
      20. INIT + SHOW WINDOW

    ===========================================================================
    Metadata
    ===========================================================================
      Script   : RemoteAppUninstaller.ps1
      Version  : 1.0
      Author   : Mohammad Omar
      Org      : Qassim University — IT Operations
      Updated  : 2026-08-05
      License  : MIT

.LINK
    https://www.linkedin.com/in/mabdulkadr/
#>
#region ========================= ASSEMBLIES & GLOBALS ======================
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

# Script-scoped UI / helpers
$script:Window     = $null
$script:OutputBox  = $null
$script:brushConv  = New-Object System.Windows.Media.BrushConverter

# Inventory/view
$Global:AllApps        = @()
$Global:AppView        = $null
$script:FilterPattern  = $null
$script:LastDetailsKey = $null

# Job + polling
$Global:UninstallJob   = $null
$Global:JobLinesSeen   = 0
$Global:UninstallTotal  = 0
$Global:UninstallDone   = 0

#endregion

#region ========================= XAML - MAIN WINDOW =========================
# Lightweight XAML: ControlTemplates for polish, NO DropShadowEffects.
$XAML = $null; [string]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Remote App Uninstaller"
    Height="860" Width="1360"
    MinHeight="600" MinWidth="1000"
    Background="#F1F5F9"
    Foreground="#0F172A"
    WindowStartupLocation="CenterScreen"
    FontFamily="Segoe UI">

    <Window.Resources>
        <!-- ===== SHADOW (stats cards only) ===== -->
        <DropShadowEffect x:Key="CardShadow" BlurRadius="8" ShadowDepth="1" Opacity="0.08" Color="#0F172A"/>

        <!-- ===== BUTTONS ===== -->
        <Style x:Key="BtnBase" TargetType="Button">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Background" Value="#E2E8F0"/>
                                <Setter Property="Foreground" Value="#94A3B8"/>
                                <Setter Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button" BasedOn="{StaticResource BtnBase}"/>

        <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#4338CA"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
        </Style>
        <Style x:Key="BtnSecondary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#F1F5F9"/>
            <Setter Property="Foreground" Value="#334155"/>
        </Style>
        <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#DC2626"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
        </Style>
        <Style x:Key="BtnGhost" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#475569"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#94A3B8"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#F1F5F9"/>
                                <Setter Property="Foreground" Value="#6366F1"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#E2E8F0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BtnDarkGhost" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#1E293B"/>
                                <Setter Property="Foreground" Value="#E2E8F0"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#334155"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ===== TYPOGRAPHY ===== -->
        <Style x:Key="H1" TargetType="TextBlock">
            <Setter Property="FontSize" Value="22"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#0F172A"/>
        </Style>
        <Style x:Key="PanelTitle" TargetType="TextBlock">
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#0F172A"/>
        </Style>
        <Style x:Key="CaptionText" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
        </Style>
        <Style x:Key="StatLabel" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style x:Key="StatValue" TargetType="TextBlock">
            <Setter Property="FontSize" Value="24"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#0F172A"/>
        </Style>

        <!-- ===== GRID HEADERS ===== -->
        <Style TargetType="GridViewColumnHeader">
            <Setter Property="Background" Value="#F8FAFC"/>
            <Setter Property="Foreground" Value="#475569"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GridViewColumnHeader">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ===== TEXTBOX ===== -->
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="2,0">
                            <ScrollViewer x:Name="PART_ContentHost"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#6366F1"/>
                                <Setter TargetName="Bd" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#94A3B8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ===== LISTVIEW ITEMS ===== -->
        <Style TargetType="ListViewItem">
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#334155"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListViewItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
                            <GridViewRowPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="ItemsControl.AlternationIndex" Value="1">
                                <Setter TargetName="Bd" Property="Background" Value="#F8FAFC"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#EEF2FF"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#C7D2FE"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#E0E7FF"/>
                                <Setter Property="Foreground" Value="#312E81"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#818CF8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ===== SIDEBAR ===== -->
        <Style x:Key="SidebarCard" TargetType="Border">
            <Setter Property="Background" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14"/>
            <Setter Property="Margin" Value="12,8,12,0"/>
        </Style>

        <Style x:Key="SidebarSectionTitle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>

        <Style x:Key="SidebarLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#475569"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>
        <Style x:Key="SidebarValue" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#6366F1"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="265"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- LEFT SIDEBAR -->
        <Border Grid.Column="0" Background="#FFFFFF" BorderBrush="#E2E8F0" BorderThickness="0,0,1,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Brand -->
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="16,20,16,14">
                    <Border Background="#6366F1" Width="38" Height="38" CornerRadius="6">
                        <TextBlock Text="R" Foreground="#FFFFFF" FontSize="20" FontWeight="Bold"
                                   VerticalAlignment="Center" HorizontalAlignment="Center"/>
                    </Border>
                    <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="Remote App Uninstaller" FontWeight="Bold" FontSize="14.5" Foreground="#0F172A"/>
                        <TextBlock Text="Device Management Tool" FontSize="10.5" Foreground="#94A3B8"/>
                    </StackPanel>
                </StackPanel>

                <!-- Nav -->
                <StackPanel Grid.Row="1" Margin="12,4">
                    <TextBlock Text="NAVIGATION" Margin="14,10,0,6" Style="{StaticResource CaptionText}" FontWeight="Bold"/>
                    <Button Content="Applications" FontWeight="SemiBold" Height="36" Margin="2"
                            HorizontalContentAlignment="Left" Padding="12,0"
                            Background="#EEF2FF" Foreground="#4338CA" BorderThickness="0"/>
                </StackPanel>

                <!-- Remote Device -->
                <Border Style="{StaticResource SidebarCard}" Grid.Row="2" VerticalAlignment="Top">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <TextBlock Text="Target Device" Style="{StaticResource SidebarSectionTitle}" Margin="0"/>
                            <Border x:Name="TargetBadge" Background="#EEF2FF" Padding="8,3" Margin="6,0,0,0" CornerRadius="10">
                                <TextBlock x:Name="TargetBadgeText" Text="This PC" FontSize="10.5" FontWeight="SemiBold" Foreground="#4338CA"/>
                            </Border>
                        </StackPanel>
                        <TextBox x:Name="PCNameBox" Height="32" Margin="0,0,0,8"
                                 ToolTip="Enter a computer name or leave empty for the local machine"/>
                        <Button x:Name="LoadAppsButton" Content="Load Applications" Height="34"
                                Style="{StaticResource BtnPrimary}"/>
                    </StackPanel>
                </Border>

                <!-- System Info + About -->
                <StackPanel Grid.Row="3" VerticalAlignment="Bottom">
                    <Border Style="{StaticResource SidebarCard}" Margin="12,0,12,8">
                        <StackPanel>
                            <Grid Margin="0,0,0,10">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Text="System Info" Style="{StaticResource SidebarSectionTitle}" Margin="0"/>
                                <Border x:Name="RemotePcStatusBadge" Grid.Column="1"
                                        Background="#ECFDF5" Padding="8,3" CornerRadius="10">
                                    <StackPanel Orientation="Horizontal">
                                        <Ellipse x:Name="RemotePcStatusDot" Width="7" Height="7" Fill="#10B981" VerticalAlignment="Center"/>
                                        <TextBlock x:Name="RemotePcStatusText" Text="Connected"
                                                   FontSize="10.5" FontWeight="SemiBold" Foreground="#065F46" Margin="5,0,0,0"/>
                                    </StackPanel>
                                </Border>
                            </Grid>

                            <UniformGrid Columns="1" Rows="4">
                                <Grid Margin="0,3">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="46"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="Device" Style="{StaticResource SidebarLabel}" FontWeight="SemiBold" Foreground="#334155"/>
                                    <Border x:Name="RemotePcDevicePill" Grid.Column="1" Background="#EEF2FF" Padding="6,3" CornerRadius="4">
                                        <TextBlock x:Name="RemotePcDeviceTxt" Text="-" Style="{StaticResource SidebarValue}"/>
                                    </Border>
                                </Grid>
                                <Grid Margin="0,3">
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock Text="IP" Style="{StaticResource SidebarLabel}" FontWeight="SemiBold" Foreground="#334155"/>
                                    </StackPanel>
                                    <Border x:Name="RemotePcIpPill" Grid.Column="1" Background="#EEF2FF" Padding="6,3" CornerRadius="4">
                                        <TextBlock x:Name="RemotePcIpTxt" Text="-" Style="{StaticResource SidebarValue}"/>
                                    </Border>
                                </Grid>
                                <Grid Margin="0,3">
                                    <TextBlock Text="User" Style="{StaticResource SidebarLabel}" FontWeight="SemiBold" Foreground="#334155"/>
                                    <Border x:Name="RemotePcUserPill" Grid.Column="1" Background="#ECFDF5" Padding="6,3" CornerRadius="4">
                                        <TextBlock x:Name="RemotePcUserTxt" Text="-" Style="{StaticResource SidebarValue}" Foreground="#065F46"/>
                                    </Border>
                                </Grid>
                                <Grid Margin="0,3">
                                    <TextBlock Text="OS" Style="{StaticResource SidebarLabel}" FontWeight="SemiBold" Foreground="#334155"/>
                                    <Border x:Name="RemotePcOsPill" Grid.Column="1" Background="#EEF2FF" Padding="6,3" CornerRadius="4">
                                        <TextBlock x:Name="RemotePcOsTxt" Text="-" Style="{StaticResource SidebarValue}"/>
                                    </Border>
                                </Grid>
                            </UniformGrid>

                            <StackPanel Margin="0,12,0,0">
                                <TextBlock Text="LAST ACTIVITY" Style="{StaticResource CaptionText}" Foreground="#94A3B8"/>
                                <TextBlock x:Name="LastActionValue" Text="Ready." Style="{StaticResource SidebarLabel}"
                                           Foreground="#10B981" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                                <TextBlock x:Name="SessionLoadedFromValue" Text="-" Style="{StaticResource SidebarLabel}"
                                           Foreground="#6366F1" Visibility="Collapsed"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource SidebarCard}" Margin="12,0,12,8">
                        <StackPanel>
                            <TextBlock Text="About" Style="{StaticResource SidebarSectionTitle}"/>
                            <TextBlock Text="Secure application inventory and uninstall tool with full logging and CSV export support."
                                       Style="{StaticResource SidebarLabel}" FontSize="11"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Footer -->
                <Border Grid.Row="4" BorderBrush="#E2E8F0" BorderThickness="0,1,0,0" Padding="14" Background="#F8FAFC">
                    <StackPanel>
                        <TextBlock Text="Qassim University" FontSize="12" FontWeight="Bold" Foreground="#0F172A"/>
                        <TextBlock Text="IT Operations" FontSize="11" Foreground="#64748B"/>
                        <TextBlock FontSize="10.5" Foreground="#94A3B8" Margin="0,6,0,0">
                            <Run Text="© 2025 · v1.0 · "/>
                            <Hyperlink x:Name="FooterLink" NavigateUri="https://www.linkedin.com/in/mabdulkadr/">Mohammad Omar</Hyperlink>
                        </TextBlock>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <!-- MAIN CONTENT -->
        <Grid Grid.Column="1" Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="180"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <StackPanel Grid.Row="0">
                <TextBlock Text="Application Manager" Style="{StaticResource H1}"/>
                <TextBlock Text="Browse, inspect, export and safely uninstall applications from local or remote Windows devices."
                           FontSize="12.5" Foreground="#475569" Margin="0,4,0,0"/>
            </StackPanel>

            <!-- Stats cards -->
            <UniformGrid Grid.Row="1" Columns="4" Margin="0,16,0,16">
                <!-- Total -->
                <Border Background="White" CornerRadius="8" Padding="16" Margin="0,0,10,0" Effect="{StaticResource CardShadow}">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="TOTAL" Style="{StaticResource StatLabel}" Foreground="#6366F1"/>
                            <TextBlock x:Name="TotalAppsValue" Text="0" Style="{StaticResource StatValue}"/>
                        </StackPanel>
                        <Border Grid.Column="1" Background="#EEF2FF" Width="40" Height="40" CornerRadius="8" VerticalAlignment="Center">
                            <TextBlock Text="&#x1F4CA;" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </Grid>
                </Border>
                <!-- MSI -->
                <Border Background="White" CornerRadius="8" Padding="16" Margin="0,0,10,0" Effect="{StaticResource CardShadow}">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="MSI" Style="{StaticResource StatLabel}" Foreground="#10B981"/>
                            <TextBlock x:Name="MsiAppsValue" Text="0" Style="{StaticResource StatValue}"/>
                        </StackPanel>
                        <Border Grid.Column="1" Background="#ECFDF5" Width="40" Height="40" CornerRadius="8" VerticalAlignment="Center">
                            <TextBlock Text="&#x1F4E6;" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </Grid>
                </Border>
                <!-- EXE/Other -->
                <Border Background="White" CornerRadius="8" Padding="16" Margin="0,0,10,0" Effect="{StaticResource CardShadow}">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="EXE / OTHER" Style="{StaticResource StatLabel}" Foreground="#F59E0B"/>
                            <TextBlock x:Name="ExeAppsValue" Text="0" Style="{StaticResource StatValue}"/>
                        </StackPanel>
                        <Border Grid.Column="1" Background="#FFFBEB" Width="40" Height="40" CornerRadius="8" VerticalAlignment="Center">
                            <TextBlock Text="&#x26A1;" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </Grid>
                </Border>
                <!-- Selected -->
                <Border Background="White" CornerRadius="8" Padding="16" Effect="{StaticResource CardShadow}">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="SELECTED" Style="{StaticResource StatLabel}" Foreground="#3B82F6"/>
                            <TextBlock x:Name="SelectedAppsValue" Text="-" Style="{StaticResource StatValue}"/>
                        </StackPanel>
                        <Border Grid.Column="1" Background="#EFF6FF" Width="40" Height="40" CornerRadius="8" VerticalAlignment="Center">
                            <TextBlock Text="&#x2713;" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </Grid>
                </Border>
            </UniformGrid>

            <!-- Apps + Details + Message Center continue... -->

"@
#endregion

#region ========================= XAML - MAIN WINDOW (Part 2) =================
$XAML += @"
            <!-- Apps + Details -->
            <Grid Grid.Row="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="5*"/>
                    <ColumnDefinition Width="4*"/>
                </Grid.ColumnDefinitions>

                <!-- Apps list -->
                <Border Grid.Column="0" Background="White" CornerRadius="8" Padding="16" Margin="0,0,10,0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="220"/>
                                <ColumnDefinition Width="64"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal">
                                <Border Width="4" Height="18" Background="#6366F1" CornerRadius="2" Margin="0,0,8,0" VerticalAlignment="Center"/>
                                <StackPanel>
                                    <TextBlock Text="Installed Applications" Style="{StaticResource PanelTitle}"/>
                                    <TextBlock x:Name="AppCountText" Text="No data loaded" Style="{StaticResource CaptionText}"/>
                                </StackPanel>
                            </StackPanel>
                            <TextBox x:Name="SearchBox" Grid.Column="2" Height="30" Margin="0,0,6,0"
                                     ToolTip="Search by name, publisher or version"/>
                            <Button x:Name="ClearSearchButton" Grid.Column="3" Content="Clear" Height="30"
                                    Style="{StaticResource BtnGhost}" FontSize="11"/>
                        </Grid>

                        <ListView x:Name="AppListView"
                                  Grid.Row="1"
                                  Margin="0,10,0,10"
                                  SelectionMode="Extended"
                                  Background="Transparent"
                                  Foreground="#334155"
                                  BorderBrush="#E2E8F0"
                                  BorderThickness="1"
                                  AlternationCount="2"
                                  ScrollViewer.HorizontalScrollBarVisibility="Auto">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="#" Width="42" DisplayMemberBinding="{Binding Index}"/>
                                    <GridViewColumn Header="Name" Width="260" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Version" Width="90" DisplayMemberBinding="{Binding Version}"/>
                                    <GridViewColumn Header="Publisher" Width="160" DisplayMemberBinding="{Binding Publisher}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>

                        <StackPanel Grid.Row="2" Margin="0,4,0,0">
                            <UniformGrid Columns="3" HorizontalAlignment="Stretch">
                                <Button x:Name="RefreshButton" Content="Reload Apps" Height="32" Margin="0,0,8,0"
                                        Style="{StaticResource BtnSecondary}"/>
                                <Button x:Name="ExportButton" Content="Export to CSV" Height="32" Margin="0,0,8,0"
                                        Style="{StaticResource BtnSecondary}"/>
                                <Button x:Name="UninstallButton" Content="Uninstall Selected" Height="32"
                                        Style="{StaticResource BtnDanger}"/>
                            </UniformGrid>

                            <StackPanel x:Name="UninstallProgressPanel" Visibility="Collapsed" Margin="0,8,0,0">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ProgressBar x:Name="UninstallProgressBar" Height="6" Minimum="0" Maximum="100" Value="0"
                                                 Foreground="#4F46E5" Background="#E2E8F0" BorderThickness="0"/>
                                    <TextBlock x:Name="UninstallProgressText" Grid.Column="1" Text="0/0"
                                               FontSize="11" Foreground="#64748B" Margin="8,0,0,0" VerticalAlignment="Center"/>
                                </Grid>
                            </StackPanel>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- Details -->
                <Border Grid.Column="1" Background="White" CornerRadius="8" Padding="16">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Orientation="Horizontal">
                            <Border Width="4" Height="18" Background="#10B981" CornerRadius="2" Margin="0,0,8,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Application Details" Style="{StaticResource PanelTitle}"/>
                        </StackPanel>
                        <TextBlock Grid.Row="1" Text="Select one or more apps to view properties."
                                   Style="{StaticResource CaptionText}" Margin="0,6,0,12" Foreground="#64748B"/>

                        <ListView x:Name="DetailsList" Grid.Row="2"
                                  Background="Transparent" BorderBrush="#E2E8F0" BorderThickness="1"
                                  AlternationCount="2" Foreground="#334155"
                                  ScrollViewer.HorizontalScrollBarVisibility="Auto">
                            <ListView.ContextMenu>
                                <ContextMenu>
                                    <MenuItem x:Name="CopyDetailsField" Header="Copy Field"/>
                                    <MenuItem x:Name="CopyDetailsValue" Header="Copy Value"/>
                                </ContextMenu>
                            </ListView.ContextMenu>
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Field" Width="155" DisplayMemberBinding="{Binding Field}"/>
                                    <GridViewColumn Header="Value" Width="270">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <TextBlock Text="{Binding Value}" TextWrapping="Wrap" VerticalAlignment="Center" Padding="4,2" FontSize="11.5"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </Grid>
                </Border>
            </Grid>

            <!-- Message Center -->
            <Border Grid.Row="3" Background="#0F172A" CornerRadius="8" Padding="14" Margin="0,14,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#10B981" Margin="0,0,8,0"/>
                            <TextBlock Text="Message Center" Foreground="#F8FAFC" FontWeight="Bold" FontSize="12" VerticalAlignment="Center"/>
                            <Border Background="#1E1B4B" Padding="4,2" CornerRadius="3" VerticalAlignment="Center" Margin="8,0,0,0">
                                <TextBlock Text="LIVE" Foreground="#6366F1" FontSize="9" FontWeight="Bold"/>
                            </Border>
                        </StackPanel>
                        <Button x:Name="CopyOutputButton" Grid.Column="2" Content="Copy"
                                Style="{StaticResource BtnDarkGhost}" Margin="0,0,4,0"/>
                        <Button x:Name="ClearOutputButton" Grid.Column="3" Content="Clear"
                                Style="{StaticResource BtnDarkGhost}"/>
                    </Grid>

                    <Rectangle Grid.Row="1" Height="1" Fill="#1E293B" Margin="0,0,0,10"/>

                    <Border Grid.Row="2" CornerRadius="6" Background="#020617" BorderBrush="#1E293B" BorderThickness="1">
                        <RichTextBox x:Name="OutputBox"
                                     Background="Transparent"
                                     Foreground="#CBD5E1"
                                     FontFamily="Cascadia Code,Consolas,monospace"
                                     FontSize="11.5"
                                     BorderThickness="0"
                                     IsReadOnly="True"
                                     IsReadOnlyCaretVisible="False"
                                     Padding="8"
                                     VerticalScrollBarVisibility="Auto"/>
                    </Border>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@
#endregion

#region ========================= XAML LOADER (SAFE) =========================
# Function: Load-XamlWindowSafe
# Parses XAML text into a WPF object graph. Throws a descriptive error on
# invalid/malformed XAML instead of failing silently.
function Load-XamlWindowSafe {
    param([Parameter(Mandatory)][string]$XamlText)

    if ([string]::IsNullOrWhiteSpace($XamlText)) {
        throw "XAML content is empty."
    }

    # Remove BOM / hidden chars (PS 5.1 friendly)
    $clean = $XamlText.Trim()
    $clean = $clean -replace "^\uFEFF", ""
    $clean = $clean -replace "[\u200B-\u200D\u2060]", ""

    try { [xml]$xml = $clean }
    catch { throw "XAML XML parse failed: $($_.Exception.Message)" }

    try {
        $reader = New-Object System.Xml.XmlNodeReader $xml
        $win = [Windows.Markup.XamlReader]::Load($reader)
        if (-not $win) { throw "XamlReader returned null." }
        return $win
    }
    catch { throw "XAML load failed: $($_.Exception.Message)" }
}
#endregion

#region ========================= CONTROL BINDING (SAFE) ======================
# Function: Get-ControlOrFail
# Looks up a named XAML control and throws if it is missing (fail-fast on
# x:Name mismatches between the XAML and the script logic).
function Get-ControlOrFail {
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][string]$Name
    )
    $c = $Window.FindName($Name)
    if (-not $c) { throw "Required control '$Name' not found in XAML." }
    return $c
}

# Build window
try { $script:Window = Load-XamlWindowSafe -XamlText $XAML }
catch {
    Write-Host "[FATAL] $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Acquire references (mandatory)
try {
    $PCNameBox           = Get-ControlOrFail $script:Window 'PCNameBox'
    $LoadAppsButton      = Get-ControlOrFail $script:Window 'LoadAppsButton'
    $RefreshButton       = Get-ControlOrFail $script:Window 'RefreshButton'
    $ExportButton        = Get-ControlOrFail $script:Window 'ExportButton'
    $UninstallButton     = Get-ControlOrFail $script:Window 'UninstallButton'
    $AppListView         = Get-ControlOrFail $script:Window 'AppListView'
    $SearchBox           = Get-ControlOrFail $script:Window 'SearchBox'
    $ClearSearchButton   = Get-ControlOrFail $script:Window 'ClearSearchButton'
    $script:OutputBox    = Get-ControlOrFail $script:Window 'OutputBox'
    $CopyOutputButton    = Get-ControlOrFail $script:Window 'CopyOutputButton'
    $ClearOutputButton   = Get-ControlOrFail $script:Window 'ClearOutputButton'

    $TotalAppsValue      = Get-ControlOrFail $script:Window 'TotalAppsValue'
    $MsiAppsValue        = Get-ControlOrFail $script:Window 'MsiAppsValue'
    $ExeAppsValue        = Get-ControlOrFail $script:Window 'ExeAppsValue'
    $SelectedAppsValue   = Get-ControlOrFail $script:Window 'SelectedAppsValue'

    $RemotePcStatusBadge    = Get-ControlOrFail $script:Window 'RemotePcStatusBadge'
    $RemotePcStatusDot      = Get-ControlOrFail $script:Window 'RemotePcStatusDot'
    $RemotePcStatusText     = Get-ControlOrFail $script:Window 'RemotePcStatusText'
    $RemotePcDeviceTxt      = Get-ControlOrFail $script:Window 'RemotePcDeviceTxt'
    $RemotePcIpTxt          = Get-ControlOrFail $script:Window 'RemotePcIpTxt'
    $RemotePcUserTxt        = Get-ControlOrFail $script:Window 'RemotePcUserTxt'
    $RemotePcOsTxt          = Get-ControlOrFail $script:Window 'RemotePcOsTxt'

    # Optional (can be null)
    $TargetBadge            = $script:Window.FindName('TargetBadge')
    $TargetBadgeText        = $script:Window.FindName('TargetBadgeText')
    $RemotePcUserPill       = $script:Window.FindName('RemotePcUserPill')
    $SessionLoadedFromValue = $script:Window.FindName('SessionLoadedFromValue')
    $LastActionValue        = $script:Window.FindName('LastActionValue')
    $FooterLink             = $script:Window.FindName('FooterLink')
    $AppCountText           = $script:Window.FindName('AppCountText')

    $UninstallProgressPanel  = $script:Window.FindName('UninstallProgressPanel')
    $UninstallProgressBar    = $script:Window.FindName('UninstallProgressBar')
    $UninstallProgressText   = $script:Window.FindName('UninstallProgressText')

    $DetailsList        = Get-ControlOrFail $script:Window 'DetailsList'

    $CopyDetailsField   = Get-ControlOrFail $script:Window 'CopyDetailsField'
    $CopyDetailsValue   = Get-ControlOrFail $script:Window 'CopyDetailsValue'
}
catch {
    Write-Host "[FATAL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Fix x:Name mismatches in XAML." -ForegroundColor Yellow
    return
}
#endregion

# Helper: pump all pending Windows messages so the window stays responsive
function Pump-UI {
    [System.Windows.Forms.Application]::DoEvents()
}

# Show window NOW — remaining init runs between Pump-UI calls
$script:Window.Show()
Pump-UI

#region ========================= TARGET HELPERS ==============================
# Function: Is-LocalTarget
# Returns $true when the given name means "this computer" (empty, ".", LOCALHOST
# or the local machine name). Used to decide local vs remote flow and the badge.
function Is-LocalTarget {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }

    $n = $Name.Trim().ToUpper()
    return ($n -in @('.', 'LOCALHOST', $env:COMPUTERNAME.ToUpper()))
}

# Function: Test-TargetReachable
# Pings (ICMP) a remote target; local targets always return $true. Used as a
# cheap pre-check before attempting a WinRM inventory call.
function Test-TargetReachable {
    param([string]$ComputerName)

    if (Is-LocalTarget $ComputerName) { return $true }
    try { return (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop) }
    catch { return $false }
}
#endregion
Pump-UI

#region ========================= FOOTER LINK (OPTIONAL) ======================
if ($FooterLink) {
    $FooterLink.Add_RequestNavigate({
        param($sender, $e)
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $e.Uri.AbsoluteUri
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {}
        $e.Handled = $true
    })
}
#endregion
Pump-UI

#region ========================= SESSION INFO (SIDEBAR) ======================
# Function: Set-Brush
# Sets a control Background from a hex color string (thread-safe helper).
function Set-Brush {
    param($control,[string]$hex)
    if ($control) { $control.Background = $script:brushConv.ConvertFromString($hex) }
}

# Function: Set-TargetBadge
# Shows "This PC" (blue) for local targets or "Remote" (orange) for remote ones
# on the "Remote Device" sidebar card.
function Set-TargetBadge {
    param([bool]$IsLocal)

    $label = if ($IsLocal) { "This PC" } else { "Remote" }

    Invoke-Ui {
        if ($TargetBadgeText) {
            $TargetBadgeText.Text = $label
            $TargetBadgeText.Foreground = $script:brushConv.ConvertFromString($(if ($IsLocal) { "#4338CA" } else { "#92400E" }))
        }
        if ($TargetBadge) {
            Set-Brush $TargetBadge ($(if ($IsLocal) { "#EEF2FF" } else { "#FFFBEB" }))
        }
    }
}

# Function: Set-RemotePcStatus
# Refreshes the "Remote PC" sidebar card: target badge, Connected/Offline status
# dot, and the Device / IP / OS info (queried locally or via WinRM).
function Set-RemotePcStatus {
    param(
        [string]$Target,
        [bool]$Connected
    )

    $displayName = if ([string]::IsNullOrWhiteSpace($Target)) { $env:COMPUTERNAME } else { $Target }
    $isLocal = Is-LocalTarget -Name $Target

    Set-TargetBadge -IsLocal $isLocal

    $ip = "-"
    $os = "-"

    if ($Connected) {
        try {
            # Shared IP detection: try Get-NetIPAddress, fall back to DNS/WMI
            function Get-PrimaryIP {
                try {
                    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                        Select-Object -First 1).IPAddress
                    if ($ip) { return $ip }
                } catch {}
                try {
                    $hostEntry = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)
                    return ($hostEntry.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notlike '127.*' } | Select-Object -First 1).ToString()
                } catch {}
                return $null
            }

            if ($isLocal) {
                $ip = Get-PrimaryIP
                $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                if ($osInfo) { $os = "{0} {1}" -f $osInfo.Caption, $osInfo.Version }
            } else {
                $info = Invoke-Command -ComputerName $Target -ScriptBlock {
                    $ipInfo = $null
                    try {
                        $ipInfo = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                            Select-Object -First 1).IPAddress
                    } catch {}
                    if (-not $ipInfo) {
                        try {
                            $hostEntry = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)
                            $ipInfo = ($hostEntry.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notlike '127.*' } | Select-Object -First 1).ToString()
                        } catch {}
                    }
                    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                    $userName = if ($env:USERDOMAIN -and $env:USERNAME) { "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME } else { $env:USERNAME }
                    [pscustomobject]@{
                        IP   = $ipInfo
                        OS   = if ($osInfo) { "{0} {1}" -f $osInfo.Caption, $osInfo.Version } else { $null }
                        User = $userName
                    }
                } -ErrorAction SilentlyContinue
                if ($info) {
                    if ($info.IP)   { $ip = $info.IP }
                    if ($info.OS)   { $os = $info.OS }
                    if ($info.User -and $RemotePcUserTxt) {
                        Invoke-Ui { $RemotePcUserTxt.Text = $info.User }
                    }
                }
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($ip)) { $ip = "-" }
    if ([string]::IsNullOrWhiteSpace($os)) { $os = "-" }

    Invoke-Ui {
        if ($RemotePcStatusDot) {
            $RemotePcStatusDot.Fill = $script:brushConv.ConvertFromString($(if ($Connected) { "#10B981" } else { "#EF4444" }))
        }
        if ($RemotePcStatusBadge) {
            Set-Brush $RemotePcStatusBadge ($(if ($Connected) { "#ECFDF5" } else { "#FEF2F2" }))
        }
        if ($RemotePcStatusText) {
            $RemotePcStatusText.Text = if ($Connected) { "Connected" } else { "Offline" }
            $RemotePcStatusText.Foreground = $script:brushConv.ConvertFromString($(if ($Connected) { "#065F46" } else { "#991B1B" }))
        }
        if ($RemotePcDeviceTxt) { $RemotePcDeviceTxt.Text = $displayName }
        if ($RemotePcIpTxt)     { $RemotePcIpTxt.Text = $ip }
        if ($RemotePcOsTxt)     { $RemotePcOsTxt.Text = $os }
    }
}

# Function: Set-SessionInfo
# Initializes the sidebar "Remote PC" card for the local session (current user,
# local device info, Connected status) before the window is shown.
function Set-SessionInfo {
    if ($RemotePcUserTxt) {
        $RemotePcUserTxt.Text = if ($env:USERDOMAIN -and $env:USERNAME) {
            "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME
        } else { $env:USERNAME }
    }

    if ($RemotePcUserPill) { Set-Brush $RemotePcUserPill "#ECFDF5" }

    # Device / IP / OS + status (connected to local machine by default)
    Set-RemotePcStatus -Target $env:COMPUTERNAME -Connected $true
}
#endregion
Pump-UI

#region ========================= UI INVOKE HELPERS ==========================
# Function: Invoke-Ui
# Runs a scriptblock on the UI (Dispatcher) thread so background job callbacks
# can safely touch WPF controls. Falls back to direct execution pre-window.
function Invoke-Ui {
    param([Parameter(Mandatory)][scriptblock]$Action)

    if ($script:Window -and $script:Window.Dispatcher) {
        $script:Window.Dispatcher.Invoke([Action]$Action)
    } else {
        & $Action
    }
}
#endregion
Pump-UI

#region ========================= LOGGER (Update-Output) ======================
# Function: Update-Output
# Writes a timestamped, color-coded line to the Message Center (or console if
# the UI is not ready). Levels: INFO, DETAIL, RESULT, WARN, ERROR, SUMMARY.
function Update-Output {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DETAIL","RESULT","SUMMARY")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $lvl = $Level.ToUpper()

    # Normalize: if message already begins with [LEVEL] (from job output)
    if ($Message -match '^\[(INFO|WARN|ERROR|DETAIL|RESULT|SUMMARY)\]\s*(.*)$') {
        $lvl     = $matches[1]
        $Message = $matches[2]
    }

    $line = "[{0}] [{1}] {2}" -f $timestamp, $lvl, $Message

    if (-not $script:OutputBox) {
        Write-Host $line
        return
    }

    $colorHex = switch ($lvl) {
        "ERROR"   { "#F87171" }
        "WARN"    { "#FBBF24" }
        "SUMMARY" { "#34D399" }
        "RESULT"  { "#60A5FA" }
        "DETAIL"  { "#C7D2FE" }
        default   { "#E6EEF7" }
    }

    $needsSpacer = ($Message -like "====*" -or $Message -like "-----*" -or $Message -like "SUMMARY*")

    Invoke-Ui {
        try {
            # A new RichTextBox starts with one empty paragraph; drop it so the
            # very first log line is visible on line 1 instead of line 2.
            if ($script:OutputBox.Document.Blocks.Count -eq 1) {
                $firstText = $script:OutputBox.Document.Blocks.FirstBlock.Text
                if ([string]::IsNullOrWhiteSpace($firstText)) {
                    $script:OutputBox.Document.Blocks.Clear()
                }
            }

            $run = New-Object System.Windows.Documents.Run($line)
            $run.Foreground = $script:brushConv.ConvertFromString($colorHex)

            $para = New-Object System.Windows.Documents.Paragraph
            $para.Margin = if ($needsSpacer) {
                New-Object System.Windows.Thickness(0,6,0,6)
            } else {
                New-Object System.Windows.Thickness(0,0,0,0)
            }

            $para.Inlines.Add($run) | Out-Null
            $script:OutputBox.Document.Blocks.Add($para)
            $script:OutputBox.ScrollToEnd()
        }
        catch {
            Write-Host $line
        }
    }
}
#endregion
Pump-UI

#region ========================= LAST ACTION (OPTIONAL) ======================
# Function: Set-LastAction
# Updates the small "Last Action" text under the Remote PC card.
function Set-LastAction {
    param([string]$Message)
    if ($LastActionValue) {
        Invoke-Ui { $LastActionValue.Text = $Message }
    }
}
#endregion
Pump-UI

#region ========================= STATS (CARDS) ===============================
# Function: Update-Stats
# Recomputes the summary cards (Total / MSI / EXE-Other / Selected) from the
# current inventory and the selection.
function Update-Stats {
    param(
        [object[]]$Apps,
        [object[]]$SelectedApps
    )

    $total = if ($Apps) { $Apps.Count } else { 0 }
    $msi = 0
    $exe = 0

    if ($Apps) {
        foreach ($a in $Apps) {
            if ($a.InstallerType -eq "MSI") { $msi++ } else { $exe++ }
        }
    }

    Invoke-Ui {
        if ($TotalAppsValue)    { $TotalAppsValue.Text    = $total }
        if ($MsiAppsValue)      { $MsiAppsValue.Text      = $msi }
        if ($ExeAppsValue)      { $ExeAppsValue.Text      = $exe }

        if ($SelectedAppsValue) {
            if (-not $SelectedApps) { $SelectedAppsValue.Text = "-" }
            else { $SelectedAppsValue.Text = $SelectedApps.Count }
        }
    }
}
#endregion
Pump-UI

#region ========================= DETAILS PANES ===============================
# Function: Get-DisplayValue
# Renders a raw value for the details grid, replacing blank/null with "-".
function Get-DisplayValue {
    param([object]$Value)
    $v = [string]$Value
    if ([string]::IsNullOrWhiteSpace($v)) { return "-" }
    return $v
}

# Function: Set-ListItems
# Binds a data row collection to a ListView/ListBox ItemsSource.
function Set-ListItems {
    param(
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][object[]]$Items
    )
    $List.ItemsSource = $Items
}
# Function: Set-ListMessage
# Shows a single informational row (Field="Info", Value=<message>) in a list.
function Set-ListMessage {
    param(
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][string]$Message
    )
    $List.ItemsSource = @([pscustomobject]@{ Field = "Info"; Value = $Message })
}

# Function: Copy-ListProperty
# Copies the selected row's <Property> value (Field or Value) to the clipboard.
function Copy-ListProperty {
    param(
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][string]$Property
    )

    $item = $List.SelectedItem
    if (-not $item) { return }

    try {
        $value = $item.$Property
        if ($null -ne $value -and [string]::IsNullOrWhiteSpace([string]$value) -eq $false) {
            [Windows.Clipboard]::SetText([string]$value)
            Update-Output ("Copied {0}" -f $Property) "INFO"
        }
    }
    catch {
        Update-Output ("Copy failed: {0}" -f $_.Exception.Message) "ERROR"
    }
}

# Function: Copy-ListRow
# Copies the selected details row as "Field: Value" (or just the value when
# both properties are the same) to the clipboard.
function Copy-ListRow {
    param(
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][string]$LeftProp,
        [Parameter(Mandatory)][string]$RightProp
    )

    $item = $List.SelectedItem
    if (-not $item) { return }

    try {
        $left = Get-DisplayValue $item.$LeftProp
        $right = Get-DisplayValue $item.$RightProp
        if ($LeftProp -eq $RightProp) {
            $text = $right
        } else {
            $text = "{0}: {1}" -f $left, $right
        }
        [Windows.Clipboard]::SetText($text)
        Update-Output ("Copied row") "INFO"
    }
    catch {
        Update-Output ("Copy failed: {0}" -f $_.Exception.Message) "ERROR"
    }
}

# Function: Reset-Details
# Clears the details pane back to the default "select apps" hint.
function Reset-Details {
    $msg = "Select app(s) to view details."
    Invoke-Ui {
        if ($DetailsList)   { Set-ListMessage -List $DetailsList -Message $msg }
    }
}

# Function: Update-Details
# Fills the details grid for the selected app(s): for a single app it shows
# the full field/value list (queried on the target if it is remote); for
# multiple apps it shows a compact comparison of common fields.
function Update-Details {
    param(
        [string]$ComputerName,
        [object[]]$SelectedApps
    )

    if (-not $SelectedApps -or $SelectedApps.Count -eq 0) {
        Reset-Details
        return
    }

    $target = if ([string]::IsNullOrWhiteSpace($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
    $isLocal = Is-LocalTarget -Name $target

    # Function: Format-RegistryPath
    function Format-RegistryPath([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { return "-" }
        return ($path -replace '^Microsoft\.PowerShell\.Core\\Registry::','')
    }

    # Function: Get-FixedUninstall
    # Shows the corrected uninstall command (I->X for MSI, silent switches added).
    function Get-FixedUninstall([string]$cmd) {
        if ([string]::IsNullOrWhiteSpace($cmd)) { return "-" }
        $c = $cmd.Trim()
        if ($c -match '(?i)\bmsiexec(\.exe)?\b') {
            $c = [Regex]::Replace($c, '(?i)/i\s*(\{[0-9A-F\-]{36}\})', '/x$1')
            if ($c -notmatch '(?i)\s/quiet\b')     { $c += ' /quiet' }
            if ($c -notmatch '(?i)\s/norestart\b') { $c += ' /norestart' }
            return $c
        }
        if ($c -match '(?i)unins.*\.exe') {
            if ($c -notmatch '(?i)\s/(verysilent|silent)\b') { $c += ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
            return $c
        }
        if ($c -match '(?i)\.exe(\s|$)' -and $c -notmatch '(?i)\s(/S|/silent|/quiet|/verysilent)\b') {
            $c += ' /S'
        }
        return $c
    }

    # Function: Get-AppDetailRows
    # Builds clean detail rows for a single app (hides empty fields).
    function Get-AppDetailRows {
        param($obj, [string]$NameFieldLabel = "Name")
        $fixedCmd = Get-FixedUninstall $obj.UninstallString
        $showFixed = ($fixedCmd -ne "-" -and $fixedCmd -ne $obj.UninstallString)

        $all = @(
            @{ Field = $NameFieldLabel;     Value = $obj.Name }
            @{ Field = "Publisher";         Value = $obj.Publisher }
            @{ Field = "Version";           Value = $obj.Version }
            @{ Field = "Install Date";      Value = $obj.InstallDate }
            @{ Field = "Installer Type";    Value = $obj.InstallerType }
            @{ Field = "Architecture";      Value = $obj.Architecture }
            @{ Field = "Scope";             Value = $obj.Scope }
            @{ Field = "Product Code";      Value = $obj.ProductCode }
            @{ Field = "Uninstall String";  Value = $obj.UninstallString }
        )
        if ($showFixed) {
            $all += @{ Field = "Corrected Command"; Value = $fixedCmd }
        }
        $all += @(
            @{ Field = "Install Location";  Value = $obj.InstallLocation }
            @{ Field = "Install Size (KB)"; Value = $obj.InstallSize }
            @{ Field = "Registry Key";      Value = (Format-RegistryPath $obj.RegistryKey) }
            @{ Field = "Info URL";          Value = $obj.URLInfoAbout }
            @{ Field = "Help Link";         Value = $obj.HelpLink }
            @{ Field = "Quiet Uninstall";   Value = $obj.QuietUninstallString }
            @{ Field = "Modify Path";       Value = $obj.ModifyPath }
            @{ Field = "Repair Path";       Value = $obj.RepairPath }
            @{ Field = "Upgrade Code";      Value = $obj.UpgradeCode }
            @{ Field = "Install Source";    Value = $obj.InstallSource }
            @{ Field = "Estimated Size (KB)"; Value = $obj.EstimatedSize }
            @{ Field = "Display Icon";      Value = $obj.DisplayIcon }
            @{ Field = "Release Type";      Value = $obj.ReleaseType }
            @{ Field = "Parent Display Name"; Value = $obj.ParentDisplayName }
            @{ Field = "Parent Key Name";   Value = $obj.ParentKeyName }
            @{ Field = "System Component";  Value = $obj.SystemComponent }
            @{ Field = "Windows Installer"; Value = $obj.WindowsInstaller }
        )
        # Show only rows with meaningful data
        $r = @()
        foreach ($row in $all) {
            $v = [string]$row.Value
            if (-not [string]::IsNullOrWhiteSpace($v) -and $v -ne "-") {
                $r += [pscustomobject]@{ Field = $row.Field; Value = $v }
            }
        }
        return $r
    }

    # Function: Get-CompactComparison
    # For multi-select: show a compact key-fields comparison.
    function Get-CompactComparison {
        param($items)
        $rows = @()
        $sep = [pscustomobject]@{ Field = ""; Value = "" }
        foreach ($item in $items) {
            $rows += [pscustomobject]@{ Field = "Application"; Value = ([string]$item.Name) }
            $rows += [pscustomobject]@{ Field = "Version";     Value = Get-DisplayValue $item.Version }
            $rows += [pscustomobject]@{ Field = "Publisher";   Value = Get-DisplayValue $item.Publisher }
            $rows += [pscustomobject]@{ Field = "Type";        Value = Get-DisplayValue $item.InstallerType }
            $rows += [pscustomobject]@{ Field = "Architecture";Value = Get-DisplayValue $item.Architecture }
            $rows += [pscustomobject]@{ Field = "Product Code";Value = Get-DisplayValue $item.ProductCode }
            $rows += $sep
        }
        return $rows
    }

    Invoke-Ui {
        if (-not $DetailsList) { return }

        if ($SelectedApps.Count -gt 1) {
            $rows = Get-CompactComparison -items $SelectedApps
            Set-ListItems -List $DetailsList -Items $rows
        } else {
            $rows = Get-AppDetailRows -obj $SelectedApps[0]
            Set-ListItems -List $DetailsList -Items $rows
        }
    }

    # Query services/drivers/tasks (local or remote)
    # Services/Drivers/Tasks removed (tabs deleted)
}
#endregion
Pump-UI

#region ========================= COLLECTION VIEW + FILTER ====================
# Function: Add-AppIndex
# Adds a 1-based "Index" note property to each app (used for the list numbering).
function Add-AppIndex {
    param([object[]]$List)

    $i = 1
    foreach ($item in ($List | Where-Object { $_ })) {
        try { $item.PSObject.Properties.Remove('Index') | Out-Null } catch {}
        Add-Member -InputObject $item -NotePropertyName Index -NotePropertyValue $i -Force
        $i++
    }
    return $List
}

# Function: Set-AppList
# Replaces the current inventory: stores it in $Global:AllApps, binds the
# ListView, resets the filter view, refreshes stats and clears the details pane.
function Set-AppList {
    param([object[]]$Apps)

    if (-not $Apps) { $Apps = @() }

    $Global:AllApps = $Apps
    $script:LastDetailsKey = $null

    if ($AppCountText) {
        Invoke-Ui { $AppCountText.Text = "{0} app{1}" -f $Apps.Count, $(if ($Apps.Count -eq 1) { "" } else { "s" }) }
    }

    Invoke-Ui {
        $AppListView.ItemsSource = $Apps
    }

    $Global:AppView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($AppListView.ItemsSource)

    Update-Stats -Apps $Apps -SelectedApps @()
    Reset-Details

    if ($SearchBox) {
        Update-Filter -FilterText $SearchBox.Text
    }
}

# Function: Update-Filter
# Applies (or clears) a case-insensitive regex filter on Name / Publisher /
# Version against the current CollectionView.
function Update-Filter {
    param([string]$FilterText)

    if (-not $Global:AppView) { return }

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        $script:FilterPattern = $null
        $Global:AppView.Filter = $null
        $Global:AppView.Refresh()
        return
    }

    $script:FilterPattern = '(?i)' + [Regex]::Escape($FilterText.Trim())

    $Global:AppView.Filter = {
        param($item)
        if (-not $item) { return $false }

        ($item.Name      -match $script:FilterPattern) -or
        ($item.Publisher -match $script:FilterPattern) -or
        ($item.Version   -match $script:FilterPattern)
    }

    $Global:AppView.Refresh()
}
#endregion
Pump-UI

#region ========================= GET-INSTALLEDAPPS ==========================
# Shared scriptblock: reads apps from registry (used for both local and remote).
$GetRegistryAppsSb = {
    param($Keys)

    $list = @()
    foreach ($Key in $Keys) {
        $list += Get-ChildItem -Path $Key -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = $_.GetValue("DisplayName")
            if (-not $dn) { return }

            $uninstall = $_.GetValue("UninstallString")
            $keyName = $_.PSChildName
            $productCode = $_.GetValue("ProductCode")
            if ([string]::IsNullOrWhiteSpace([string]$productCode) -and $keyName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                $productCode = $keyName
            }
            $arch = if ($Key -match 'WOW6432Node') { 'x86' } else { 'x64' }
            $installerType = if ($uninstall -match '(?i)\bmsiexec(\.exe)?\b') { "MSI" } else { "EXE/Other" }
            $uninstall = [Regex]::Replace($uninstall, '(?i)/i\s*(\{)', '/x$1')

            [PSCustomObject]@{
                Name            = $dn
                Publisher       = $_.GetValue("Publisher")
                Version         = $_.GetValue("DisplayVersion")
                InstallDate     = $_.GetValue("InstallDate")
                UninstallString = $uninstall
                QuietUninstallString = $_.GetValue("QuietUninstallString")
                ModifyPath      = $_.GetValue("ModifyPath")
                RepairPath      = $_.GetValue("RepairPath")
                InstallLocation = $_.GetValue("InstallLocation")
                InstallSource   = $_.GetValue("InstallSource")
                InstallSize     = $_.GetValue("InstallSize")
                EstimatedSize   = $_.GetValue("EstimatedSize")
                DisplayIcon     = $_.GetValue("DisplayIcon")
                RegistryKey     = $_.PSPath
                ProductCode     = $productCode
                UpgradeCode     = $_.GetValue("UpgradeCode")
                URLInfoAbout    = $_.GetValue("URLInfoAbout")
                HelpLink        = $_.GetValue("HelpLink")
                ReleaseType     = $_.GetValue("ReleaseType")
                ParentDisplayName = $_.GetValue("ParentDisplayName")
                ParentKeyName   = $_.GetValue("ParentKeyName")
                SystemComponent = $_.GetValue("SystemComponent")
                WindowsInstaller = $_.GetValue("WindowsInstaller")
                InstallerType   = $installerType
                Architecture    = $arch
                Scope           = "Machine"
            }
        }
    }

    $list | Sort-Object Name
}

# Function: Get-InstalledApps
# Returns the list of installed applications for a target. Local targets read
# both HKLM Uninstall views directly; remote targets first do a ping check,
# then an Invoke-Command over WinRM. Every path updates the Remote PC card
# (Connected/Offline) and returns an array (empty on failure).
function Get-InstalledApps {
    param([string]$ComputerName)

    if ([string]::IsNullOrWhiteSpace($ComputerName)) { $ComputerName = $env:COMPUTERNAME }
    $isLocal = Is-LocalTarget -Name $ComputerName

    $Keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    if ($isLocal) {
        Update-Output ("Loading apps from local machine ({0})..." -f $ComputerName) "INFO"
        $apps = Add-AppIndex -List (& $GetRegistryAppsSb -Keys $Keys)
        Set-RemotePcStatus -Target $ComputerName -Connected $true
        Update-Output ("Retrieved {0} app(s) from local machine." -f $apps.Count) "RESULT"
        return $apps
    }

    # Remote
    Update-Output ("Checking connectivity to '{0}'..." -f $ComputerName) "DETAIL"
    if (-not (Test-TargetReachable -ComputerName $ComputerName)) {
        Update-Output ("Failed to reach {0}." -f $ComputerName) "ERROR"
        Set-RemotePcStatus -Target $ComputerName -Connected $false
        return @()
    }

    Update-Output ("Connected. Fetching registry-based apps from {0}..." -f $ComputerName) "INFO"

    try {
        $apps = Invoke-Command -ComputerName $ComputerName -ScriptBlock $GetRegistryAppsSb -ArgumentList (,$Keys) -ErrorAction Stop
    } catch {
        Update-Output ("Failed to query apps on {0}: {1}" -f $ComputerName, $_.Exception.Message) "ERROR"
        Set-RemotePcStatus -Target $ComputerName -Connected $false
        return @()
    }

    if (-not $apps) { $apps = @() }
    $apps = Add-AppIndex -List $apps

    Set-RemotePcStatus -Target $ComputerName -Connected $true
    Update-Output ("Retrieved {0} app(s) from {1}." -f $apps.Count, $ComputerName) "RESULT"
    return $apps
}
#endregion
Pump-UI

#region ========================= CONFIRMATION DIALOG =========================
# Function: Show-UninstallConfirmation
# Shows a Yes/No modal dialog listing the target and the selected app names
# (first 4 + count). Returns $true only when the user confirms.
function Show-UninstallConfirmation {
    param(
        [string]$TargetName,
        [string[]]$AppNames
    )

    $targetLabel = if ([string]::IsNullOrWhiteSpace($TargetName)) {
        "Local ($env:COMPUTERNAME)"
    } else { $TargetName }

    $count = if ($AppNames) { $AppNames.Count } else { 0 }
    $preview = @($AppNames | Where-Object { $_ } | Select-Object -First 4)
    $more = $count - $preview.Count
    $listText = ($preview -join "`r`n")
    if ($more -gt 0) { $listText += "`r`n+ $more more..." }
    if ([string]::IsNullOrWhiteSpace($listText)) { $listText = "(no names available)" }

    $ConfirmXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Confirm Uninstall"
        Height="310" Width="520"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#F1F5F9"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="DlgBtn" TargetType="Button">
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Opacity" Value="0.9"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="DlgBtnPrimary" TargetType="Button" BasedOn="{StaticResource DlgBtn}">
            <Setter Property="Background" Value="#4338CA"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
        </Style>
        <Style x:Key="DlgBtnDanger" TargetType="Button" BasedOn="{StaticResource DlgBtn}">
            <Setter Property="Background" Value="#DC2626"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
        </Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <StackPanel Orientation="Horizontal">
                <Border Background="#FEF2F2" Width="32" Height="32" CornerRadius="6">
                    <TextBlock Text="!" FontSize="16" FontWeight="Bold" Foreground="#EF4444"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Margin="10,0,0,0">
                    <TextBlock Text="Confirm Uninstall" FontSize="18" FontWeight="Bold" Foreground="#0F172A"/>
                    <TextBlock x:Name="TargetLabelTxt" FontSize="11.5" Foreground="#64748B" Margin="0,2,0,0"/>
                </StackPanel>
            </StackPanel>
        </StackPanel>

        <Border Grid.Row="1" Background="#FFFFFF" CornerRadius="6" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1">
            <StackPanel>
                <TextBlock x:Name="SummaryTxt" FontSize="13" FontWeight="SemiBold" Foreground="#0F172A" TextWrapping="Wrap"/>
                <TextBlock Text="Apps:" Margin="0,10,0,4" FontWeight="SemiBold" Foreground="#475569" FontSize="11"/>
                <ScrollViewer Height="80" VerticalScrollBarVisibility="Auto">
                    <TextBlock x:Name="AppListTxt" FontSize="12" Foreground="#334155" TextWrapping="Wrap"/>
                </ScrollViewer>
            </StackPanel>
        </Border>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="CancelBtn"  Content="Cancel"  Style="{StaticResource DlgBtnPrimary}" IsCancel="True"/>
            <Button x:Name="ConfirmBtn" Content="Yes, Uninstall" Style="{StaticResource DlgBtnDanger}" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$ConfirmXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($reader)

    ($dlg.FindName('TargetLabelTxt')).Text = "Target: $targetLabel"
    ($dlg.FindName('SummaryTxt')).Text     = "Proceed to uninstall $count app(s)?"
    ($dlg.FindName('AppListTxt')).Text     = $listText

    ($dlg.FindName('ConfirmBtn')).Add_Click({ $dlg.DialogResult = $true;  $dlg.Close() })
    ($dlg.FindName('CancelBtn')).Add_Click({  $dlg.DialogResult = $false; $dlg.Close() })

    if ($script:Window) { $dlg.Owner = $script:Window }

    $result = $dlg.ShowDialog()
    return ($result -eq $true)
}
#endregion
Pump-UI

#region ========================= UNINSTALL SCRIPTBLOCK =======================
# Runs in a background job: normalize uninstall, run, verify, winget fallback, cleanup

$UninstallScriptBlock = {
    param(
        [string]$ComputerName,
        [object[]]$AppList
    )

    if ([string]::IsNullOrWhiteSpace($ComputerName)) { $ComputerName = $env:COMPUTERNAME }
    $ErrorActionPreference = 'Stop'

    # Function: Write-Log
    function Write-Log {
        param(
            [string]$Message,
            [ValidateSet('INFO','WARN','ERROR','DETAIL','RESULT','SUMMARY')]
            [string]$Level = 'INFO'
        )
        Write-Output ("[{0}] {1}" -f $Level, $Message)
    }

    # Function: Test-IsLocalComputer
    # True for '.', 'LOCALHOST' or the local machine name.
    function Test-IsLocalComputer { param([string]$Name) return ($Name.ToUpper() -in @('.', 'LOCALHOST', $env:COMPUTERNAME.ToUpper())) }
    # Function: Escape-Regex
    # Escapes free text so it can be used safely in a regex.
    function Escape-Regex([string]$Text) { if ([string]::IsNullOrWhiteSpace($Text)) { return '' }; return [Regex]::Escape($Text) }

    # Function: Add-SilentSwitches
    # Appends the best known quiet switches for the detected installer type:
    # MSI (/quiet /norestart), Inno (/VERYSILENT /SUPPRESSMSGBOXES /NORESTART),
    # and generic EXE (/S) when no silent flag is present.
    function Add-SilentSwitches([string]$cmd) {
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $cmd }
        $c = $cmd.Trim()

        if ($c -match '(?i)\bmsiexec(\.exe)?\b') {
            $guid = $null
            if ($c -match '(?i)\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}') { $guid = $matches[0] }
            if ($guid) { return ("msiexec.exe /x {0} /quiet /norestart" -f $guid) }

            $c = [Regex]::Replace($c, '(?i)/i\s*(\{[0-9A-F\-]{36}\})', '/x$1')
            if ($c -notmatch '(?i)\s/quiet\b')     { $c += ' /quiet' }
            if ($c -notmatch '(?i)\s/norestart\b') { $c += ' /norestart' }
            return $c
        }

        if ($c -match '(?i)unins.*\.exe') {
            if ($c -notmatch '(?i)\s/(verysilent|silent)\b') { $c += ' /VERYSILENT' }
            if ($c -notmatch '(?i)\s/suppressmsgboxes\b')    { $c += ' /SUPPRESSMSGBOXES' }
            if ($c -notmatch '(?i)\s/norestart\b')           { $c += ' /NORESTART' }
            return $c
        }

        if ($c -match '(?i)\.exe(\s|$)' -and $c -notmatch '(?i)\s(/S|/silent|/quiet|/verysilent)\b') {
            $c += ' /S'
        }
        return $c
    }

    # Function: Split-UninstallCommand
    # Splits an uninstall string into its executable and argument parts so it
    # can be run without a shell (avoids shell-injection issues).
    function Split-UninstallCommand([string]$cmd) {
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
        $exe = $null; $args = ""
        if ($cmd -match '^\s*\"([^\"]+)\"(.*)$') {
            $exe  = $matches[1]
            $args = ($matches[2]).Trim()
        } elseif ($cmd -match '^\s*(.+?\.exe)\s+(.*)$') {
            $exe  = $matches[1]
            $args = $matches[2]
        } else {
            $parts = $cmd -split '\s+', 2
            $exe = $parts[0]
            if ($parts.Count -gt 1) { $args = $parts[1] }
        }
        [pscustomobject]@{ Exe=$exe; Args=$args }
    }

    # Function: Invoke-TargetCommand
    # Runs a scriptblock either locally or via Invoke-Command, forwarding arguments.
    function Invoke-TargetCommand {
        param([string]$Target, [scriptblock]$ScriptBlock, [object[]]$Arguments)
        if (Test-IsLocalComputer $Target) {
            if ($Arguments -and $Arguments.Count -gt 0) { return (& $ScriptBlock $Arguments) }
            return (& $ScriptBlock)
        }
        return (Invoke-Command -ComputerName $Target -ScriptBlock $ScriptBlock -ArgumentList $Arguments -ErrorAction SilentlyContinue)
    }

    # Function: Test-AppStillInstalled
    # Checks the HKLM Uninstall views (local or via WinRM) to see whether an
    # app whose DisplayName matches <Name> still exists. If verification cannot
    # run (unreachable / WinRM error) it returns $true to avoid a false success.
    function Test-AppStillInstalled {
        param([string]$Target,[string]$Name)

        $rx = Escape-Regex $Name
        $sb = {
            param($rx)
            $RegPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
            )
            foreach ($r in $RegPaths) {
                Get-ChildItem -Path $r -ErrorAction SilentlyContinue | ForEach-Object {
                    $dn = $_.GetValue("DisplayName")
                    if ($dn -and ($dn -match $rx)) { return $true }
                }
            }
            return $false
        }

        $result = Invoke-TargetCommand -Target $Target -ScriptBlock $sb -Arguments @($rx)
        if ($null -eq $result) { return $true }
        return $result
    }

    # Function: Remove-RegistryLeftovers
    # Deletes leftover HKLM Uninstall keys whose DisplayName matches the app.
    function Remove-RegistryLeftovers {
        param([string]$Target,[string]$AppName)

        $rx = Escape-Regex $AppName
        $sb = {
            param($rx)
            $removed = @()
            $RegPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
            )
            foreach ($r in $RegPaths) {
                Get-ChildItem -Path $r -ErrorAction SilentlyContinue | ForEach-Object {
                    $dn = $_.GetValue("DisplayName")
                    if ($dn -and ($dn -match $rx)) {
                        $removed += ($_.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::','')
                        try { Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    }
                }
            }
            return $removed
        }
        return (Invoke-TargetCommand -Target $Target -ScriptBlock $sb -Arguments @($rx))
    }

    # Function: Remove-FolderMatches
    # Deletes top-level folders under the given roots whose name matches the app.
    function Remove-FolderMatches {
        param([string]$Target,[string]$AppName,[string[]]$Roots)

        $rx = Escape-Regex $AppName
        $sb = {
            param($rx,$Roots)
            $removed = @()
            foreach ($root in $Roots) {
                if (-not (Test-Path $root)) { continue }
                Get-ChildItem -Path $root -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $rx } |
                    ForEach-Object {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    }
            }
            return $removed
        }
        return (Invoke-TargetCommand -Target $Target -ScriptBlock $sb -Arguments @($rx, $Roots))
    }

    # Function: Remove-StartMenuMatches
    # Removes matching Start Menu shortcuts/folders (All Users + each user profile).
    function Remove-StartMenuMatches {
        param([string]$Target,[string]$AppName)

        $rx = Escape-Regex $AppName
        $sb = {
            param($rx)
            $removed = @()

            $allUsers = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
            if (Test-Path $allUsers) {
                Get-ChildItem -Path $allUsers -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.PSIsContainer -and ($_.Name -match $rx)) {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    } elseif (-not $_.PSIsContainer -and $_.Extension -eq '.lnk' -and ($_.Name -match $rx)) {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
                    }
                }
            }

            $userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
            foreach ($u in $userDirs) {
                $userSM = Join-Path $u.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
                if (-not (Test-Path $userSM)) { continue }

                Get-ChildItem -Path $userSM -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.PSIsContainer -and ($_.Name -match $rx)) {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    } elseif (-not $_.PSIsContainer -and $_.Extension -eq '.lnk' -and ($_.Name -match $rx)) {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
                    }
                }
            }

            return $removed
        }
        return (Invoke-TargetCommand -Target $Target -ScriptBlock $sb -Arguments @($rx))
    }

    # Function: Remove-AppDataMatches
    # Removes matching app-data folders/shortcuts under each user profile.
    function Remove-AppDataMatches {
        param([string]$Target,[string]$AppName)

        $rx = Escape-Regex $AppName
        $sb = {
            param($rx)
            $removed = @()
            $skip = @('Public','Default','All Users')

            $userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notin $skip }

            foreach ($u in $userDirs) {
                $appData = Join-Path $u.FullName "AppData"
                if (-not (Test-Path $appData)) { continue }

                Get-ChildItem -Path $appData -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { ($_.Name -match $rx) -and (($_.Extension -eq '.exe') -or ($_.Extension -eq '.lnk')) } |
                    ForEach-Object {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
                    }

                Get-ChildItem -Path $appData -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $rx } |
                    ForEach-Object {
                        $removed += $_.FullName
                        try { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    }
            }

            return $removed
        }
        return (Invoke-TargetCommand -Target $Target -ScriptBlock $sb -Arguments @($rx))
    }

    # Function: Try-WinGetUninstall
    # Fallback: tries to uninstall via `winget uninstall --exact --silent`.
    # Returns $true only if winget is present and the uninstall succeeds.
    function Try-WinGetUninstall {
        param([string]$Target,[string]$AppName)

        $sbHas = { [bool](Get-Command winget -ErrorAction SilentlyContinue) }
        $sbRun = {
            param($n)
            Start-Process "winget" -ArgumentList ("uninstall --name `"{0}`" --exact --silent --accept-source-agreements --accept-package-agreements" -f $n) `
                -Wait -WindowStyle Hidden | Out-Null
        }

        $isLocal = Test-IsLocalComputer $Target
        $ok = $false

        try {
            $ok = if ($isLocal) { & $sbHas } else { Invoke-Command -ComputerName $Target -ScriptBlock $sbHas -ErrorAction SilentlyContinue }
        } catch { $ok = $false }

        if (-not $ok) { return $false }

        try {
            if ($isLocal) { & $sbRun $AppName }
            else { Invoke-Command -ComputerName $Target -ScriptBlock $sbRun -ArgumentList $AppName -ErrorAction SilentlyContinue | Out-Null }
            return $true
        } catch { return $false }
    }

    # Function: Remove-Application
    # Orchestrates the removal of a single app: stops matching processes, runs
    # the (silent) uninstall command, verifies removal, cleans up registry /
    # folder / start-menu / appdata leftovers, and reports a Status object.
    function Remove-Application {
        param([string]$Target,[psobject]$AppObject)

        $appName = [string]$AppObject.Name
        $uninstall = [string]$AppObject.UninstallString
        $isLocal = Test-IsLocalComputer $Target
        $rx = Escape-Regex $appName

        Write-Log "-----" "INFO"
        Write-Log ("Attempting to remove '{0}' on {1}..." -f $appName, $Target) "INFO"

        if (-not $isLocal) {
            if (-not (Test-Connection -ComputerName $Target -Count 1 -Quiet)) {
                Write-Log ("Cannot reach {0}. Skipping '{1}'." -f $Target, $appName) "ERROR"
                return [pscustomobject]@{ Status='Failed'; Note='Unreachable'; Details=@() }
            }
        }

        # Stop processes (best-effort)
        Write-Log ("Stopping processes matching '{0}'..." -f $appName) "DETAIL"
        try {
            $stopProcSb = {
                param($rx)
                Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
                    $match = $_.ProcessName -match $rx
                    $desc = try { $_.Description } catch { $null }
                    if (-not $match -and $desc) { $match = $desc -match $rx }
                    if ($match) { Stop-Process -InputObject $_ -Force -ErrorAction SilentlyContinue | Out-Null }
                }
            }
            if ($isLocal) {
                & $stopProcSb $rx
            } else {
                Invoke-Command -ComputerName $Target -ScriptBlock $stopProcSb -ArgumentList $rx -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}

        $details = New-Object System.Collections.Generic.List[string]

        # Uninstall
        if ([string]::IsNullOrWhiteSpace($uninstall)) {
            Write-Log ("No UninstallString found for '{0}'." -f $appName) "WARN"
        } else {
            $uninstall = Add-SilentSwitches $uninstall
            Write-Log ("Running uninstall command: {0}" -f $uninstall) "INFO"
            $details.Add("Uninstall: $uninstall") | Out-Null

            $split = Split-UninstallCommand $uninstall
            if ($split -and $split.Exe) {
                $exePath = $split.Exe
                $exeArgs = $split.Args

                if (-not [System.IO.Path]::IsPathRooted($exePath)) {
                    @("$env:SystemRoot\System32\$exePath", "$env:SystemRoot\SysWOW64\$exePath", "$env:SystemRoot\$exePath") | ForEach-Object {
                        if (-not (Test-Path $exePath) -and (Test-Path $_)) { $exePath = $_ }
                    }
                }

                try {
                    if ($isLocal) {
                        if (Test-Path $exePath) {
                            Start-Process -FilePath $exePath -ArgumentList $exeArgs -Wait -WindowStyle Hidden | Out-Null
                        } else {
                            Write-Log ("Executable not found: {0}" -f $exePath) "ERROR"
                            $details.Add("Missing EXE: $exePath") | Out-Null
                        }
                    } else {
                        Invoke-Command -ComputerName $Target -ScriptBlock {
                            param($p,$a)
                            if (Test-Path $p) { Start-Process -FilePath $p -ArgumentList $a -Wait -WindowStyle Hidden | Out-Null }
                            else { Write-Output ("[ERROR] Executable not found: " + $p) }
                        } -ArgumentList $exePath,$exeArgs -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_ }
                    }
                } catch {
                    Write-Log ("Uninstall execution failed: {0}" -f $_.Exception.Message) "ERROR"
                    $details.Add("Uninstall error: $($_.Exception.Message)") | Out-Null
                }
            } else {
                Write-Log ("Could not parse uninstall command for '{0}'." -f $appName) "ERROR"
                $details.Add("Parse uninstall failed") | Out-Null
            }
        }

        # Verify (regex match)
        $stillInstalled = Test-AppStillInstalled -Target $Target -Name $appName

        # WinGet fallback
        if ($stillInstalled) {
            Write-Log ("Traditional uninstall may have failed for '{0}'. Trying WinGet..." -f $appName) "WARN"
            $wgRan = Try-WinGetUninstall -Target $Target -AppName $appName
            if ($wgRan) {
                Start-Sleep -Seconds 1
                $stillInstalled = Test-AppStillInstalled -Target $Target -Name $appName
                if (-not $stillInstalled) { Write-Log ("'{0}' removed via WinGet fallback." -f $appName) "RESULT" }
                else { Write-Log ("WinGet could not remove '{0}'." -f $appName) "ERROR" }
            } else {
                Write-Log "WinGet not available or failed to start." "WARN"
            }
        } else {
            Write-Log ("'{0}' removed via uninstall." -f $appName) "RESULT"
        }

        # Cleanup (only do cleanup when uninstall succeeded OR still installed but user wants force cleanup? Here we do best-effort always.)
        Write-Log ("Cleanup: registry/files/shortcuts/appdata for '{0}'..." -f $appName) "DETAIL"

        $regRemoved = Remove-RegistryLeftovers -Target $Target -AppName $appName
        foreach ($r in ($regRemoved | Where-Object { $_ })) { $details.Add("Registry removed: $r") | Out-Null }

        $pfRemoved = Remove-FolderMatches -Target $Target -AppName $appName -Roots @("C:\Program Files","C:\Program Files (x86)")
        foreach ($p in ($pfRemoved | Where-Object { $_ })) { $details.Add("ProgramFiles removed: $p") | Out-Null }

        $smRemoved = Remove-StartMenuMatches -Target $Target -AppName $appName
        foreach ($s in ($smRemoved | Where-Object { $_ })) { $details.Add("StartMenu removed: $s") | Out-Null }

        $adRemoved = Remove-AppDataMatches -Target $Target -AppName $appName
        foreach ($a in ($adRemoved | Where-Object { $_ })) { $details.Add("AppData removed: $a") | Out-Null }

        if (-not $stillInstalled) {
            return [pscustomobject]@{ Status='Success'; Note='Removed'; Details=$details.ToArray() }
        }
        return [pscustomobject]@{ Status='Failed'; Note='Still detected after uninstall'; Details=$details.ToArray() }
    }

    # Batch loop
    $Results = New-Object System.Collections.ArrayList
    Write-Log ("Job started. Target={0} Apps={1}" -f $ComputerName, ($AppList.Count)) "SUMMARY"
    Write-Log ("===== Starting batch uninstall on {0} for {1} app(s)... =====" -f $ComputerName, ($AppList.Count)) "INFO"

    foreach ($app in $AppList) {
        try {
            $res = Remove-Application -Target $ComputerName -AppObject $app
            $Results.Add([pscustomobject]@{
                App     = $app.Name
                Status  = $res.Status
                Note    = $res.Note
                Details = $res.Details
            }) | Out-Null

            Write-Log ("RESULT: {0} -> {1} {2}" -f $app.Name, $res.Status, $res.Note) "RESULT"
        }
        catch {
            $Results.Add([pscustomobject]@{
                App     = $app.Name
                Status  = "Failed"
                Note    = $_.Exception.Message
                Details = @()
            }) | Out-Null
            Write-Log ("RESULT: {0} -> Failed {1}" -f $app.Name, $_.Exception.Message) "ERROR"
        }
    }

    $successCount = ($Results | Where-Object { $_.Status -eq 'Success' }).Count
    $failCount    = ($Results | Where-Object { $_.Status -ne 'Success' }).Count

    Write-Log ("SUMMARY: Completed on {0} | Success: {1} | Failed: {2}" -f $ComputerName, $successCount, $failCount) "SUMMARY"
    Write-Log ("===== Uninstallation completed for {0} app(s) on {1}. =====" -f ($AppList.Count), $ComputerName) "INFO"
}
#endregion
Pump-UI

#region ========================= JOB POLLING (DispatcherTimer) ===============
$PollTimer = New-Object System.Windows.Threading.DispatcherTimer
$PollTimer.Interval = [TimeSpan]::FromMilliseconds(500)

# Function: Show-UninstallSummaryDialog
# Displays the modal "Uninstall Summary" dialog (title, subtitle, line list)
# used by the job poller when the uninstall job finishes.
function Show-UninstallSummaryDialog {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string[]]$Lines
    )

    $summaryXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Uninstall Summary"
        Width="580" Height="420"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#F1F5F9"
        FontFamily="Segoe UI">
    <Grid Margin="16">
        <Border Background="White" CornerRadius="8" Padding="20">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,6">
                    <Border x:Name="SummaryIcon" Width="40" Height="40" CornerRadius="8" VerticalAlignment="Center">
                        <TextBlock x:Name="SummaryIconTxt" Text="&#x2713;" FontSize="20" FontWeight="Bold"
                                   Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel Margin="12,0,0,0">
                        <TextBlock x:Name="SummaryTitle" FontWeight="Bold" FontSize="17" Foreground="#0F172A"/>
                        <TextBlock x:Name="SummarySubtitle" FontSize="12" Foreground="#64748B"/>
                    </StackPanel>
                </StackPanel>

                <StackPanel x:Name="SummaryStats" Grid.Row="1" Orientation="Horizontal" Margin="0,6,0,12">
                    <Border Background="#ECFDF5" Padding="10,4" CornerRadius="6" Margin="0,0,8,0">
                        <TextBlock x:Name="SuccessCount" Text="0 succeeded" FontSize="11.5" FontWeight="SemiBold" Foreground="#065F46"/>
                    </Border>
                    <Border Background="#FEF2F2" Padding="10,4" CornerRadius="6">
                        <TextBlock x:Name="FailCount" Text="0 failed" FontSize="11.5" FontWeight="SemiBold" Foreground="#991B1B"/>
                    </Border>
                </StackPanel>

                <Border Grid.Row="2" Background="#F8FAFC" CornerRadius="6" BorderBrush="#E2E8F0" BorderThickness="1" Padding="12">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="SummaryBody" />
                    </ScrollViewer>
                </Border>

                <Button x:Name="CloseBtn" Grid.Row="3" Content="Close" Width="90" Height="34"
                        Background="#4338CA" Foreground="#FFFFFF" FontWeight="SemiBold"
                        BorderThickness="0" Cursor="Hand" FontSize="12"
                        HorizontalAlignment="Right" Margin="0,14,0,0"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$summaryXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($reader)

    ($dlg.FindName('SummaryTitle')).Text = $Title
    ($dlg.FindName('SummarySubtitle')).Text = $Subtitle

    # Count results
    $succ = 0; $fail = 0
    $bodyPanel = $dlg.FindName('SummaryBody')
    if ($Lines -and $Lines.Count -gt 0) {
        foreach ($ln in $Lines) {
            if ($ln -like "*Success*" -or $ln -like "*Removed*") { $succ++ }
            elseif ($ln -like "*Failed*") { $fail++ }

            $row = New-Object System.Windows.Controls.StackPanel
            $row.Orientation = 'Horizontal'
            $row.Margin = '0,2,0,2'

            $icon = New-Object System.Windows.Controls.TextBlock
            $icon.Width = 18
            $icon.FontSize = 12
            if ($ln -like "*Success*" -or $ln -like "*Removed*") {
                $icon.Text = '+'; $icon.Foreground = $script:brushConv.ConvertFromString("#10B981"); $icon.FontWeight = 'Bold'
            } elseif ($ln -like "*Failed*") {
                $icon.Text = '!'; $icon.Foreground = $script:brushConv.ConvertFromString("#EF4444"); $icon.FontWeight = 'Bold'
            } else {
                $icon.Text = '-'; $icon.Foreground = $script:brushConv.ConvertFromString("#94A3B8")
            }
            $row.AddChild($icon) | Out-Null

            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $ln
            $tb.TextWrapping = 'Wrap'
            $tb.FontSize = 11.5
            $tb.Margin = '4,0,0,0'
            if ($ln -like "*Success*" -or $ln -like "*Removed*") {
                $tb.Foreground = $script:brushConv.ConvertFromString("#065F46")
            } elseif ($ln -like "*Failed*") {
                $tb.Foreground = $script:brushConv.ConvertFromString("#991B1B")
            } else {
                $tb.Foreground = $script:brushConv.ConvertFromString("#334155")
            }
            $row.AddChild($tb) | Out-Null
            $bodyPanel.Children.Add($row) | Out-Null
        }
    } else {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "No details returned."
        $tb.Margin = '0,3,0,3'
        $tb.Foreground = $script:brushConv.ConvertFromString("#94A3B8")
        $bodyPanel.Children.Add($tb) | Out-Null
    }

    ($dlg.FindName('SuccessCount')).Text = "$succ succeeded"
    ($dlg.FindName('FailCount')).Text = "$fail failed"

    # Color the header icon based on results
    $iconBorder = $dlg.FindName('SummaryIcon')
    $iconText = $dlg.FindName('SummaryIconTxt')
    if ($fail -eq 0 -and $succ -gt 0) {
        $iconBorder.Background = $script:brushConv.ConvertFromString("#10B981")
        $iconText.Text = '+'
    } elseif ($succ -eq 0 -and $fail -gt 0) {
        $iconBorder.Background = $script:brushConv.ConvertFromString("#EF4444")
        $iconText.Text = '!'
    } else {
        $iconBorder.Background = $script:brushConv.ConvertFromString("#F59E0B")
        $iconText.Text = '~'
    }

    ($dlg.FindName('CloseBtn')).Add_Click({ $dlg.Close() })
    if ($script:Window) { $dlg.Owner = $script:Window }
    $dlg.ShowDialog() | Out-Null
}

$PollTimer.Add_Tick({
    if (-not $Global:UninstallJob) { return }

    # stream new lines
    $lines = Receive-Job -Job $Global:UninstallJob -Keep -ErrorAction SilentlyContinue
    if ($lines) {
        $start = $Global:JobLinesSeen
        if ($start -lt $lines.Count) {
            foreach ($l in $lines[$start..($lines.Count - 1)]) {
                if ($l -is [bool] -or $l -is [System.Diagnostics.Process]) { continue }
                $txt = $l.ToString()
                Update-Output $txt
                if ($txt -match 'RESULT:') { $Global:UninstallDone++ }
            }
            $Global:JobLinesSeen = $lines.Count
            # Update progress bar
            if ($Global:UninstallTotal -gt 0) {
                $pct = [math]::Min(100, [math]::Floor($Global:UninstallDone / $Global:UninstallTotal * 100))
                Invoke-Ui {
                    if ($UninstallProgressBar) { $UninstallProgressBar.Value = $pct }
                    if ($UninstallProgressText) { $UninstallProgressText.Text = "{0}/{1}" -f $Global:UninstallDone, $Global:UninstallTotal }
                }
            }
        }
    }

    # completion
    if ($Global:UninstallJob.State -in @('Completed','Failed','Stopped')) {
        $PollTimer.Stop()

        $allLines = Receive-Job -Job $Global:UninstallJob -Keep -ErrorAction SilentlyContinue
        $state = $Global:UninstallJob.State
        $reason = $Global:UninstallJob.JobStateInfo.Reason

        if ($state -eq 'Failed' -and $reason) {
            Update-Output ("Job ended. State: {0}. Reason: {1}" -f $state, $reason.Message) "ERROR"
        } else {
            Update-Output ("Job ended. State: {0}." -f $state) "INFO"
        }

        # Build summary
        $strings = @()
        foreach ($x in ($allLines | Where-Object { $_ -and ($_ -isnot [bool]) })) { $strings += $x.ToString() }

        $summary = $strings | Where-Object { $_ -like "[SUMMARY]*" -or $_ -like "[RESULT]*" -or $_ -like "[DETAIL]*" }
        $subtitle = ($summary | Where-Object { $_ -like "[SUMMARY]*" } | Select-Object -First 1)
        if (-not $subtitle) { $subtitle = "Summary not available." }

        $body = @()
        if ($summary) { $body = $summary | Where-Object { $_ -notlike $subtitle } }

        # Cleanup job
        try { Remove-Job -Job $Global:UninstallJob -Force | Out-Null } catch {}
        $Global:UninstallJob = $null
        $Global:JobLinesSeen = 0
        $Global:UninstallTotal = 0
        $Global:UninstallDone  = 0

        # Hide progress
        Invoke-Ui {
            if ($UninstallProgressPanel) { $UninstallProgressPanel.Visibility = 'Collapsed' }
            if ($UninstallProgressBar)   { $UninstallProgressBar.Value = 100 }
        }

        # Show summary dialog
        Show-UninstallSummaryDialog -Title "Uninstall summary" -Subtitle $subtitle -Lines $body

        # Refresh inventory after uninstall
        $c = if ($PCNameBox.Text) { $PCNameBox.Text.Trim() } else { $env:COMPUTERNAME }
        $apps = Get-InstalledApps -ComputerName $c
        Set-AppList -Apps $apps
        if ($SessionLoadedFromValue) { $SessionLoadedFromValue.Text = $c }
        Set-LastAction "Refreshed app list after uninstall."
    }
})

# Start timer once (it only acts when a job exists)
$PollTimer.Start()
#endregion
Pump-UI

#region ========================= BUTTON HANDLERS =============================
# Shared helper: loads apps from target, updates UI, and returns app list.
function Invoke-LoadApps {
    param(
        [string]$ActionLabel
    )

    $c = if ($PCNameBox.Text) { $PCNameBox.Text.Trim() } else { $env:COMPUTERNAME }
    if ([string]::IsNullOrWhiteSpace($c)) { $c = $env:COMPUTERNAME }

    Update-Output ("{0} clicked. Target='{1}'" -f $ActionLabel, $c) "DETAIL"

    $apps = Get-InstalledApps -ComputerName $c
    Set-AppList -Apps $apps

    if ($SessionLoadedFromValue) { $SessionLoadedFromValue.Text = $c }
    Update-Output ("{0} complete. Apps={1}" -f $ActionLabel, $apps.Count) "RESULT"
    return $apps
}

# Load Apps
$LoadAppsButton.Add_Click({
    try {
        $result = Invoke-LoadApps -ActionLabel "Load"
        Set-LastAction ("Loaded {0} app(s)." -f $result.Count)
    }
    catch {
        Update-Output ("Load failed: {0}" -f $_.Exception.Message) "ERROR"
        if ($_.ScriptStackTrace) { Update-Output ("Stack: {0}" -f $_.ScriptStackTrace) "DETAIL" }
    }
})

# Refresh Apps
$RefreshButton.Add_Click({
    try {
        Invoke-LoadApps -ActionLabel "Reload" | Out-Null
        Set-LastAction "Reloaded app list."
    }
    catch {
        Update-Output ("Refresh failed: {0}" -f $_.Exception.Message) "ERROR"
        if ($_.ScriptStackTrace) { Update-Output ("Stack: {0}" -f $_.ScriptStackTrace) "DETAIL" }
    }
})

# Uninstall Selected
$UninstallButton.Add_Click({
    try {
        # prevent concurrent job
        if ($Global:UninstallJob -and $Global:UninstallJob.State -notin @('Completed','Failed','Stopped')) {
            Update-Output "Another uninstall job is currently running. Please wait..." "WARN"
            return
        }

        $selected = @($AppListView.SelectedItems)
        if (-not $selected -or $selected.Count -eq 0) {
            Update-Output "No applications selected." "WARN"
            return
        }

        $c = if ($PCNameBox.Text) { $PCNameBox.Text.Trim() } else { $env:COMPUTERNAME }
        if ([string]::IsNullOrWhiteSpace($c)) { $c = $env:COMPUTERNAME }

        $flow = if (Is-LocalTarget $c) { "LOCAL" } else { "REMOTE" }
        Update-Output ("Selected flow: {0} -> {1}" -f $flow, $c) "INFO"

        $names = $selected | ForEach-Object { $_.Name }
        if (-not (Show-UninstallConfirmation -TargetName $c -AppNames $names)) {
            Update-Output "Uninstall cancelled by user." "INFO"
            return
        }

        Update-Output ("Launching uninstall job for {0} app(s) on {1}..." -f $selected.Count, $c) "INFO"
        Set-LastAction ("Uninstalling {0} app(s)..." -f $selected.Count)

        # Show progress bar
        $Global:UninstallTotal = $selected.Count
        $Global:UninstallDone  = 0
        Invoke-Ui {
            if ($UninstallProgressPanel) { $UninstallProgressPanel.Visibility = 'Visible' }
            if ($UninstallProgressBar)   { $UninstallProgressBar.Value = 0; $UninstallProgressBar.Maximum = 100 }
            if ($UninstallProgressText)  { $UninstallProgressText.Text = "0/{0}" -f $selected.Count }
        }

        # Start job
        $Global:UninstallJob = Start-Job -ScriptBlock $UninstallScriptBlock -ArgumentList $c, $selected
        $Global:JobLinesSeen = 0
    }
    catch {
        Update-Output ("Uninstall start failed: {0}" -f $_.Exception.Message) "ERROR"
        if ($_.ScriptStackTrace) { Update-Output ("Stack: {0}" -f $_.ScriptStackTrace) "DETAIL" }
    }
})

# Export CSV
$ExportButton.Add_Click({
    try {
        $apps = if ($Global:AppView) { @($Global:AppView | Where-Object { $_ }) } else { @($AppListView.ItemsSource) }
        if (-not $apps -or $apps.Count -eq 0) {
            Update-Output "No applications loaded to export." "WARN"
            return
        }

        Add-Type -AssemblyName System.Windows.Forms

        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "CSV files (*.csv)|*.csv"
        $safeDevice = if ($SessionLoadedFromValue -and $SessionLoadedFromValue.Text -and $SessionLoadedFromValue.Text -ne "-") {
            $SessionLoadedFromValue.Text
        } else { $env:COMPUTERNAME }
        $dlg.FileName = "{0}-{1}-apps.csv" -f $safeDevice, (Get-Date -Format "yyyyMMdd-HHmmss")

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $apps | Export-Csv -Path $dlg.FileName -NoTypeInformation
            Update-Output ("Exported {0} app(s) to '{1}'" -f $apps.Count, $dlg.FileName) "RESULT"
            Set-LastAction "Exported app list."
        }
    }
    catch {
        Update-Output ("Export failed: {0}" -f $_.Exception.Message) "ERROR"
        if ($_.ScriptStackTrace) { Update-Output ("Stack: {0}" -f $_.ScriptStackTrace) "DETAIL" }
    }
})
#endregion
Pump-UI

#region ========================= UI EVENTS ===================================
# Search filtering
if ($SearchBox) {
    $SearchBox.Add_TextChanged({
        Update-Filter -FilterText $SearchBox.Text
    })
}

if ($ClearSearchButton) {
    $ClearSearchButton.Add_Click({
        if ($SearchBox) { $SearchBox.Text = "" }
        Update-Filter -FilterText ""
    })
}

# Context menu copy helpers (details grids)
if ($CopyDetailsField) { $CopyDetailsField.Add_Click({ Copy-ListProperty -List $DetailsList -Property "Field" }) }
if ($CopyDetailsValue) { $CopyDetailsValue.Add_Click({ Copy-ListProperty -List $DetailsList -Property "Value" }) }

# Double-click + Ctrl+C copy (Field: Value)
if ($DetailsList) {
    $DetailsList.Add_MouseDoubleClick({ Copy-ListRow -List $DetailsList -LeftProp "Field" -RightProp "Value" })
    $DetailsList.Add_PreviewKeyDown({
        if (($_.Key -eq 'C') -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            Copy-ListRow -List $DetailsList -LeftProp "Field" -RightProp "Value"
            $_.Handled = $true
        }
    })
}

# Selection -> update counters + auto-show details (no button needed)
$AppListView.Add_SelectionChanged({
    $selected = @($AppListView.SelectedItems)

    Update-Stats -Apps $Global:AllApps -SelectedApps $selected

    if (-not $selected -or $selected.Count -eq 0) {
        $script:LastDetailsKey = $null
        Reset-Details
        return
    }

    # Skip re-rendering when the same selection is still active
    $key = ($selected | ForEach-Object { $_.Name } | Where-Object { $_ }) -join '|'
    if ($key -eq $script:LastDetailsKey) { return }
    $script:LastDetailsKey = $key

    Invoke-Ui {
        if ($DetailsList) { Set-ListMessage -List $DetailsList -Message "Loading details, please wait..." }
    }

    try {
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-Details -ComputerName $PCNameBox.Text -SelectedApps $selected
    }
    finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
})

# Message Center: copy / clear
if ($CopyOutputButton) {
    $CopyOutputButton.Add_Click({
        try {
            $range = New-Object System.Windows.Documents.TextRange($script:OutputBox.Document.ContentStart, $script:OutputBox.Document.ContentEnd)
            if ($range.Text) {
                [Windows.Clipboard]::SetText($range.Text)
                Update-Output "Copied Message Center to clipboard." "INFO"
            } else {
                Update-Output "Message Center is empty." "WARN"
            }
        }
        catch {
            Update-Output ("Copy failed: {0}" -f $_.Exception.Message) "ERROR"
        }
    })
}
if ($ClearOutputButton) {
    $ClearOutputButton.Add_Click({
        try {
            Invoke-Ui { $script:OutputBox.Document.Blocks.Clear() }
            Update-Output "Message Center cleared." "INFO"
        }
        catch {
            Update-Output ("Clear failed: {0}" -f $_.Exception.Message) "ERROR"
        }
    })
}

# Enter in PCNameBox triggers Load
$PCNameBox.Add_KeyDown({
    if ($_.Key -eq 'Enter') {
        $LoadAppsButton.RaiseEvent(
            (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))
        )
    }
})

# Keep the "stretch" column of each grid filling the available width
$script:Window.Add_SizeChanged({
    try {
        if ($AppListView -and $AppListView.View -and $AppListView.View.Columns.Count -ge 4) {
            $cols = $AppListView.View.Columns
            $fixed = $cols[0].Width + $cols[2].Width + $cols[3].Width + 16
            $w = $AppListView.ActualWidth - $fixed
            if ($w -gt 80) { $cols[1].Width = $w }
        }
    } catch {}
    try {
        if ($DetailsList -and $DetailsList.View -and $DetailsList.View.Columns.Count -ge 2) {
            $cols = $DetailsList.View.Columns
            $w = $DetailsList.ActualWidth - $cols[0].Width - 16
            if ($w -gt 80) { $cols[1].Width = $w }
        }
    } catch {}
})
#endregion
Pump-UI

#region ========================= INIT + SHOW WINDOW ==========================
# Session pills
Set-SessionInfo

# Initial state
$Global:AllApps = @()
$Global:AppView = $null
$script:FilterPattern = $null

Update-Stats -Apps @() -SelectedApps @()
Reset-Details
Set-LastAction "Ready."
Update-Output "Ready." "INFO"

# Defer heavy registry scan until window is fully rendered (one-shot timer)
$AutoLoadTimer = New-Object System.Windows.Threading.DispatcherTimer
$AutoLoadTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:AutoLoadTimerRef = $AutoLoadTimer
$AutoLoadTimer.Add_Tick({
    $script:AutoLoadTimerRef.Stop()
    Update-Output "Scanning registry for installed applications..." "DETAIL"
    Set-LastAction "Scanning installed apps..."
    try {
        $apps = Get-InstalledApps -ComputerName $env:COMPUTERNAME
        Set-AppList -Apps $apps
        Set-LastAction ("Loaded {0} app(s) from this PC." -f $apps.Count)
        Update-Output ("Auto-loaded {0} app(s) from this PC." -f $apps.Count) "RESULT"
    }
    catch {
        Update-Output ("Auto-load failed: {0}" -f $_.Exception.Message) "ERROR"
    }
})
$AutoLoadTimer.Start()

# Window already shown; enter WPF message pump (blocks until window closes)
$script:Window.Add_Closed({ [System.Windows.Threading.Dispatcher]::ExitAllFrames() })
[System.Windows.Threading.Dispatcher]::Run()
#endregion
