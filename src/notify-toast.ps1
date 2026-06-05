param(
  [string]$Title = 'Claude Code',
  [string]$Message = 'Notification'
)

$ErrorActionPreference = 'SilentlyContinue'

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

# AUMID of the built-in Windows PowerShell shortcut. Toasts render under "Windows PowerShell".
$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$nodes = $template.GetElementsByTagName('text')
$nodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
$nodes.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null

$toastNode = $template.SelectSingleNode('/toast')
$toastNode.SetAttribute('activationType', 'protocol') | Out-Null
$toastNode.SetAttribute('launch', 'claudefocus:open') | Out-Null

$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
