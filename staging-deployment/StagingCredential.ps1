Set-StrictMode -Version Latest

if ($null -eq ('Ezytire.StagingCredential.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Ezytire.StagingCredential
{
    public sealed class CredentialData
    {
        public string UserName { get; private set; }
        public string Password { get; private set; }

        public CredentialData(string userName, string password)
        {
            UserName = userName;
            Password = password;
        }
    }

    public static class NativeMethods
    {
        private const UInt32 GenericCredentialType = 1;
        private const UInt32 LocalMachinePersistence = 2;
        private const int ErrorNotFound = 1168;

        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime
        {
            public UInt32 LowDateTime;
            public UInt32 HighDateTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Credential
        {
            public UInt32 Flags;
            public UInt32 Type;
            public IntPtr TargetName;
            public IntPtr Comment;
            public FileTime LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public IntPtr TargetAlias;
            public IntPtr UserName;
        }

        [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredReadW(
            string target,
            UInt32 type,
            UInt32 flags,
            out IntPtr credential);

        [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWriteW(
            ref Credential credential,
            UInt32 flags);

        [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDeleteW(
            string target,
            UInt32 type,
            UInt32 flags);

        [DllImport("Advapi32.dll", SetLastError = true)]
        private static extern void CredFree(IntPtr credential);

        public static CredentialData ReadCredential(string target)
        {
            IntPtr credentialPointer;
            if (!CredReadW(target, GenericCredentialType, 0, out credentialPointer))
            {
                int errorCode = Marshal.GetLastWin32Error();
                if (errorCode == ErrorNotFound)
                {
                    return null;
                }

                throw new Win32Exception(errorCode);
            }

            try
            {
                Credential credential = Marshal.PtrToStructure<Credential>(credentialPointer);
                string userName = Marshal.PtrToStringUni(credential.UserName);
                string password = credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0
                    ? null
                    : Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);

                return new CredentialData(userName, password);
            }
            finally
            {
                CredFree(credentialPointer);
            }
        }

        public static void WriteCredential(string target, string userName, string password)
        {
            if (String.IsNullOrWhiteSpace(target))
            {
                throw new ArgumentException("A credential target is required.", "target");
            }

            if (String.IsNullOrWhiteSpace(userName))
            {
                throw new ArgumentException("A user name is required.", "userName");
            }

            if (String.IsNullOrEmpty(password))
            {
                throw new ArgumentException("A password is required.", "password");
            }

            byte[] passwordBytes = Encoding.Unicode.GetBytes(password);
            IntPtr targetNamePointer = IntPtr.Zero;
            IntPtr userNamePointer = IntPtr.Zero;
            IntPtr credentialBlobPointer = IntPtr.Zero;
            try
            {
                targetNamePointer = Marshal.StringToCoTaskMemUni(target);
                userNamePointer = Marshal.StringToCoTaskMemUni(userName);
                credentialBlobPointer = Marshal.AllocCoTaskMem(passwordBytes.Length);
                Marshal.Copy(passwordBytes, 0, credentialBlobPointer, passwordBytes.Length);

                Credential credential = new Credential
                {
                    Type = GenericCredentialType,
                    TargetName = targetNamePointer,
                    UserName = userNamePointer,
                    CredentialBlob = credentialBlobPointer,
                    CredentialBlobSize = (UInt32)passwordBytes.Length,
                    Persist = LocalMachinePersistence
                };

                if (!CredWriteW(ref credential, 0))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                if (credentialBlobPointer != IntPtr.Zero)
                {
                    Marshal.Copy(new byte[passwordBytes.Length], 0, credentialBlobPointer, passwordBytes.Length);
                    Marshal.FreeCoTaskMem(credentialBlobPointer);
                }

                if (targetNamePointer != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(targetNamePointer);
                }

                if (userNamePointer != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(userNamePointer);
                }

                Array.Clear(passwordBytes, 0, passwordBytes.Length);
            }
        }

        public static void DeleteCredential(string target)
        {
            if (!CredDeleteW(target, GenericCredentialType, 0))
            {
                int errorCode = Marshal.GetLastWin32Error();
                if (errorCode != ErrorNotFound)
                {
                    throw new Win32Exception(errorCode);
                }
            }
        }
    }
}
'@
}

function Get-StagingCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $credentialData = [Ezytire.StagingCredential.NativeMethods]::ReadCredential($Target)
    if ($null -eq $credentialData) {
        throw "No Windows Credential Manager entry exists for '$Target'. Run Set-StagingCredential.ps1 first."
    }

    if ([string]::IsNullOrWhiteSpace($credentialData.UserName)) {
        throw "Windows Credential Manager entry '$Target' does not contain a user name."
    }

    if ([string]::IsNullOrEmpty($credentialData.Password)) {
        throw "Windows Credential Manager entry '$Target' does not contain a password."
    }

    $securePassword = ConvertTo-SecureString -String $credentialData.Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($credentialData.UserName, $securePassword)
}

function Set-StagingCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )

    $networkCredential = $Credential.GetNetworkCredential()
    [Ezytire.StagingCredential.NativeMethods]::WriteCredential(
        $Target,
        $networkCredential.UserName,
        $networkCredential.Password)
}

function Remove-StagingCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    [Ezytire.StagingCredential.NativeMethods]::DeleteCredential($Target)
}
