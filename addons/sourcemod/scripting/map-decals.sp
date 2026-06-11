#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools_trace>
#include <sdktools_engine>
#include <sdktools_entinput>
#include <sdktools_tempents>
#include <sdktools_functions>
#include <sdktools_stringtables>

#include <clientprefs>
#include <convar_class>
#include <flags-core>
#include <printer>

#define MAP_DECALS_PLUGIN   "map-decals"
#define MAP_DECALS_TAG      "[Decals]"
#define MAX_DECALS          128
#define MAX_MAP_DECALS      4096
#define DECAL_SIZES         4
#define DECAL_DIST          8192.0

char gS_Sizes[DECAL_SIZES][16] = { "Small", "Medium", "Large", "Extra Large" };

printer_colors_t gS_ChatStrings;

Convar gCV_PluginName = null;
Convar gCV_PluginFlags = null;

Cookie gH_EnabledCookie = null;
Cookie gH_RedrawCookie = null;
Cookie gH_UnlitCookie = null;

bool gB_Enabled[MAXPLAYERS+1];
bool gB_Redraw[MAXPLAYERS+1];
bool gB_Unlit[MAXPLAYERS+1];
int gI_LastMainMenuIndx[MAXPLAYERS+1];
int gI_DecalsPlaced[MAXPLAYERS+1];

enum struct decal_entry_t
{
    int iPrecacheIndex;
    int iPrecacheIndexLM;
    char sPath[PLATFORM_MAX_PATH];
    char sPathLM[PLATFORM_MAX_PATH];
}

enum struct decal_data_t
{
    int iIndex;
    char sName[32];
    char sFlags[16];
    ArrayList aEntries;
}

enum struct decal_pe_t
{
    int iPrecacheIndex;
    int iPrecacheIndexLM;
    float fPos[3];
}

ArrayList gA_Decals = null;
ArrayList gA_PersistentDecals = null;

public Plugin myinfo =
{
	name = "[Fun!] map decals",
	author = "happydez",
	description = "✿˘✧.*☆*✲☆⋆❤˘━✧.*",
	version = "1.0.0",
	url = "https://github.com/happydez"
}

public void OnPluginStart()
{
    gCV_PluginName = new Convar("map_decals_name", "Map Decals", "Display name in the flags system.");
    gCV_PluginFlags = new Convar("map_decals_flags", "", "Available flags (a-z). Empty = auto-detect from config.");
    Convar.AutoExecConfig();

    gH_EnabledCookie = new Cookie("map_decals_enabled", "map_decals_enabled", CookieAccess_Protected);
    gH_RedrawCookie = new Cookie("map_decals_redraw", "map_decals_redraw", CookieAccess_Protected);
    gH_UnlitCookie = new Cookie("map_decals_unlit", "map_decals_unlit", CookieAccess_Protected);

    RegConsoleCmd("sm_decals", Command_Decal, "");

    RegConsoleCmd("sm_decals_enabled", Command_DecalsEnabled, "");
    RegConsoleCmd("sm_decals_redraw", Command_DecalsRedraw, "");
    RegConsoleCmd("sm_decals_unlit", Command_DecalsUnlit, "");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && AreClientCookiesCached(i))
        {
            OnClientCookiesCached(i);
        }
    }

    PP_GetColors(gS_ChatStrings);
}

public void OnMapStart()
{
    DeleteDecals();
    if (!LoadDecals())
    {
        SetFailState("[map-decals] Cannot open \"configs/fun/map-decals.cfg\". Make sure file exists and readable.");
    }

    RegisterWithCore();

    if (gA_PersistentDecals == null)
    {
        gA_PersistentDecals = new ArrayList(sizeof(decal_pe_t));
    }
}

public void PP_OnColorsLoaded()
{
    PP_GetColors(gS_ChatStrings);
}

public void OnClientConnected(int client)
{
    gI_LastMainMenuIndx[client] = 0;
    gI_DecalsPlaced[client] = 0;
}

public void OnClientCookiesCached(int client)
{
    char cookie[2];
    gH_EnabledCookie.Get(client, cookie, 2);
    if (cookie[0] == '\0')
    {
        gB_Enabled[client] = true;
        gH_EnabledCookie.Set(client, "1");
    }
    else
    {
        gB_Enabled[client] = (StringToInt(cookie) == 1);
    }

    gH_RedrawCookie.Get(client, cookie, 2);
    if (cookie[0] == '\0')
    {
        gB_Redraw[client] = true;
        gH_RedrawCookie.Set(client, "1");
    }
    else
    {
        gB_Redraw[client] = (StringToInt(cookie) == 1);
    }

    gH_UnlitCookie.Get(client, cookie, 2);
    if (cookie[0] == '\0')
    {
        gB_Unlit[client] = false;
        gH_UnlitCookie.Set(client, "0");
    }
    else
    {
        gB_Unlit[client] = (StringToInt(cookie) == 1);
    }
}

public void OnClientPutInServer(int client)
{
    if (AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
        return;
    }

    gB_Enabled[client] = true;
    gB_Redraw[client] = true;
    gB_Unlit[client] = false;
}

public Action Command_DecalsEnabled(int client, int args)
{
    if (IsValidClient(client))
    {
        gB_Enabled[client] = !gB_Enabled[client];
        gH_EnabledCookie.Set(client, gB_Enabled[client] ? "1" : "0");

        if (gB_Enabled[client])
        {
            PP_PrintToChat(client, "%s%s%s map-decals is now %senabled", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sVariable2);
        }
        else
        {
            PP_PrintToChat(client, "%s%s%s map-decals is now %sdisabled", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sWarning);
        }
    }

    return Plugin_Handled;
}

public Action Command_DecalsRedraw(int client, int args)
{
    if (IsValidClient(client))
    {
        gB_Redraw[client] = !gB_Redraw[client];
        gH_RedrawCookie.Set(client, gB_Redraw[client] ? "1" : "0");

        if (gB_Redraw[client])
        {
            PP_PrintToChat(client, "%s%s%s map-decals redraw is now %senabled", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sVariable2);
        }
        else
        {
            PP_PrintToChat(client, "%s%s%s map-decals redraw is now %sdisabled", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sWarning);
        }
    }

    return Plugin_Handled;
}

public Action Command_DecalsUnlit(int client, int args)
{
    if (IsValidClient(client))
    {
        gB_Unlit[client] = !gB_Unlit[client];
        gH_UnlitCookie.Set(client, gB_Unlit[client] ? "1" : "0");

        if (gB_Unlit[client])
        {
            PP_PrintToChat(client, "%s%s%s UnlitGeneric is now %senabled", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sVariable2);
        }
        else
        {
            PP_PrintToChat(client, "%s%s%s UnlitGeneric is now %sdisabled %s(LightmappedGeneric will be used)", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable);
        }
    }

    return Plugin_Handled;
}

public void Flags_OnNewMapStarted()
{
    delete gA_PersistentDecals;

    if (gA_PersistentDecals == null)
    {
        gA_PersistentDecals = new ArrayList(sizeof(decal_pe_t));
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        gI_DecalsPlaced[i] = 0;
    }
}

void RegisterWithCore()
{
    char name[64], flags[32];
    gCV_PluginName.GetString(name, sizeof(name));
    gCV_PluginFlags.GetString(flags, sizeof(flags));

    if (flags[0] == '\0')
    {
        BuildAvailableFlags(flags, sizeof(flags));
    }

    Flags_RegisterPlugin(MAP_DECALS_PLUGIN, name, flags, true, "Decals/map", MAX_MAP_DECALS);
}

void BuildAvailableFlags(char[] out, int maxlen)
{
    bool seen[26];
    for (int i = 0; i < 26; i++)
    {
        seen[i] = false;
    }

    int len = 0;
    for (int i = 0; i < gA_Decals.Length; i++)
    {
        decal_data_t decal;
        gA_Decals.GetArray(i, decal);

        int flen = strlen(decal.sFlags);
        for (int j = 0; j < flen; j++)
        {
            int c = decal.sFlags[j];
            if ('a' <= c <= 'z')
            {
                int idx = c - 'a';
                if (!seen[idx] && len + 1 < maxlen)
                {
                    seen[idx] = true;
                    out[len++] = c;
                }
            }
        }
    }

    out[len] = '\0';
}

public void OnClientPostAdminCheck(int client)
{
    if ((gB_Enabled[client] && gB_Redraw[client]) && (gA_PersistentDecals != null))
    {
        for (int i = 0; i < gA_PersistentDecals.Length; i++)
        {
            decal_pe_t dpe;
            gA_PersistentDecals.GetArray(i, dpe);
            int idx = (gB_Unlit[client] && dpe.iPrecacheIndex > 0) ? dpe.iPrecacheIndex : (dpe.iPrecacheIndexLM > 0 ? dpe.iPrecacheIndexLM : dpe.iPrecacheIndex);
            TE_SetupDecal(dpe.fPos, idx);
            TE_SendToClient(client);
        }
    }
}

public Action Command_Decal(int client, int args)
{
    if (IsValidClient(client))
    {
        Decals_OpenMainDecalMenu(client);
    }

    return Plugin_Handled;
}

void Decals_OpenMainDecalMenu(int client, int displayAt = 0)
{
    Menu menu = new Menu(Decals_MainMenu_Handler);

    char dflags[32]; int dlimit;
    bool dAccess = Flags_GetForClient(client, MAP_DECALS_PLUGIN, dflags, sizeof(dflags), dlimit);

    char titleBuf[256];
    if (dAccess)
    {
        if (dlimit == -1)
        {
            FormatEx(titleBuf, sizeof(titleBuf), "✿˘✧.*☆*✲☆⋆˘━✧.*❤\n \nUsed: %d | Remaining: Unlimited\n \n", gI_DecalsPlaced[client]);
        }
        else
        {
            int remaining = dlimit - gI_DecalsPlaced[client];
            if (remaining < 0) remaining = 0;
            FormatEx(titleBuf, sizeof(titleBuf), "✿˘✧.*☆*✲☆⋆˘━✧.*❤\n \nUsed: %d | Remaining: %d | Limit: %d\n \n", gI_DecalsPlaced[client], remaining, dlimit);
        }
    }
    else
    {
        FormatEx(titleBuf, sizeof(titleBuf), "✿˘✧.*☆*✲☆⋆˘━✧.*❤\n \nNo access\n \n");
    }

    menu.SetTitle(titleBuf);

    if (gB_Enabled[client])
    {
        menu.AddItem("de1", "Decals Enabled: [+]");
    }
    else
    {
        menu.AddItem("de1", "Decals Enabled: [-]");
    }

    if (gB_Redraw[client])
    {
        menu.AddItem("dre1", "Reconnection Redraw: [+]", gB_Enabled[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }
    else
    {
        menu.AddItem("dre1", "Reconnection Redraw: [-]", gB_Enabled[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    if (gB_Unlit[client])
    {
        if (gA_Decals.Length > 0)
        {
            menu.AddItem("un1", "UnlitGeneric: [+]\n \n", gB_Enabled[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
        }
        else
        {
            menu.AddItem("un1", "UnlitGeneric: [+]\n \nNo decals", gB_Enabled[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
        }
    }
    else
    {
        if (gA_Decals.Length > 0)
        {
            menu.AddItem("un1", "UnlitGeneric: [-]\n \n", gB_Enabled[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
        }
        else
        {
            menu.AddItem("un1", "UnlitGeneric: [-]\n \nNo decals", gB_Enabled[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
        }
    }

    char buff[48];
    for (int i = 0; i < gA_Decals.Length; i++)
    {
        decal_data_t decal;
        gA_Decals.GetArray(i, decal);

        bool ok = CheckClientDecalAccess(client, decal.sFlags);
        if (ok)
        {
            Format(buff, sizeof(buff), "%s", decal.sName);
        }
        else
        {
            Format(buff, sizeof(buff), "%s (No Access)", decal.sName);
        }

        char indx[4];
        IntToString(i, indx, sizeof(indx));
        menu.AddItem(indx, buff, (!gB_Enabled[client] ? ITEMDRAW_DISABLED : (ok ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED)));
    }

    menu.Pagination = 7;
    menu.ExitButton = true;
    menu.DisplayAt(client, displayAt, MENU_TIME_FOREVER);
}

public int Decals_MainMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[8];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "de1"))
        {
            FakeClientCommand(client, "sm_decals_enabled");
            Decals_OpenMainDecalMenu(client);
        }
        else if (StrEqual(info, "dre1"))
        {
            FakeClientCommand(client, "sm_decals_redraw");
            Decals_OpenMainDecalMenu(client);
        }
        else if (StrEqual(info, "un1"))
        {
            FakeClientCommand(client, "sm_decals_unlit");
            Decals_OpenMainDecalMenu(client);
        }
        else
        {
            int indx = StringToInt(info);
            decal_data_t decal;
            gA_Decals.GetArray(indx, decal);
            gI_LastMainMenuIndx[client] = indx;
            Decals_OpenDecalMenu(client, decal);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public void Decals_OpenDecalMenu(int client, decal_data_t decal)
{
    Menu menu = new Menu(Decals_DecalMenu_Handler);

    menu.SetTitle("%s\n \n", decal.sName);

    bool ok = CheckClientDecalAccess(client, decal.sFlags);

    char buff[8];
    for (int i = 0; i < DECAL_SIZES; i++)
    {
        decal_entry_t decalEntry;
        decal.aEntries.GetArray(i, decalEntry);
        Format(buff, sizeof(buff), "%c%d", gS_Sizes[i][0], decal.iIndex);
        bool hasAny = (strlen(decalEntry.sPath) > 0) || (strlen(decalEntry.sPathLM) > 0);
        menu.AddItem(buff, gS_Sizes[i], (hasAny && ok) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Decals_DecalMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
    char info[8], decalSize[2], decalIndex[4];
    menu.GetItem(item, info, sizeof(info));

    decalSize[0] = info[0];
    decalSize[1] = '\0';
    strcopy(decalIndex, sizeof(decalIndex), info[1]);
    int decalIdx = StringToInt(decalIndex);

    if (action == MenuAction_Select)
    {
        if (decalIdx < 0 || decalIdx >= gA_Decals.Length)
        {
            PP_PrintToChat(client, "%s%s%s Invalid %sdecal index", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sVariable);
            return 0;
        }

        decal_data_t decal;
        gA_Decals.GetArray(decalIdx, decal);

        bool ok = CheckClientDecalAccess(client, decal.sFlags);
        if (!ok)
        {
            PP_PrintToChat(client, "%s%s%s %sNo access", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sWarning);
            Decals_OpenDecalMenu(client, decal);
            return 0;
        }

        char cflags[32]; int climit;
        if (Flags_GetForClient(client, MAP_DECALS_PLUGIN, cflags, sizeof(cflags), climit) && climit != -1 && gI_DecalsPlaced[client] >= climit)
        {
            PP_PrintToChat(client, "%s%s%s %sDecal limit reached %s(%s%d%s/%s%d%s)", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gI_DecalsPlaced[client], gS_ChatStrings.sText, gS_ChatStrings.sVariable2, climit, gS_ChatStrings.sText);
            Decals_OpenDecalMenu(client, decal);
            return 0;
        }

        float pos[3], dist = 0.0;
        bool hit = GetClientAimTargetEx(client, pos, dist);

        if (hit && dist <= DECAL_DIST)
        {
            int sizeIndex = -1;
            if (StrEqual(decalSize, "S"))
            {
                sizeIndex = 0;
            }
            else if (StrEqual(decalSize, "M"))
            {
                sizeIndex = 1;
            }
            else if (StrEqual(decalSize, "L"))
            {
                sizeIndex = 2;
            }
            else if (StrEqual(decalSize, "E"))
            {
                sizeIndex = 3;
            }

            if (sizeIndex >= 0 && sizeIndex < decal.aEntries.Length)
            {
                decal_entry_t decalEntry;
                decal.aEntries.GetArray(sizeIndex, decalEntry);

                if (decalEntry.iPrecacheIndex > 0 || decalEntry.iPrecacheIndexLM > 0)
                {
                    if (gA_PersistentDecals.Length > MAX_MAP_DECALS)
                    {
                        PP_PrintToChatAll("%s%s%s decal was %snot persisted %sbecause the maximum number of decals was reached %s(%d)", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, MAX_MAP_DECALS);
                    }
                    else
                    {
                        decal_pe_t dpe;
                        dpe.iPrecacheIndex = decalEntry.iPrecacheIndex;
                        dpe.iPrecacheIndexLM = decalEntry.iPrecacheIndexLM;
                        dpe.fPos[0] = pos[0];
                        dpe.fPos[1] = pos[1];
                        dpe.fPos[2] = pos[2];
                        gA_PersistentDecals.PushArray(dpe);
                    }

                    for (int i = 1; i <= MaxClients; i++)
                    {
                        if (!IsClientInGame(i) || IsFakeClient(i) || !gB_Enabled[i])
                        {
                            continue;
                        }

                        int idx = (gB_Unlit[i] && decalEntry.iPrecacheIndex > 0) ? decalEntry.iPrecacheIndex : (decalEntry.iPrecacheIndexLM > 0 ? decalEntry.iPrecacheIndexLM : decalEntry.iPrecacheIndex);
                        if (idx <= 0)
                        {
                            continue;
                        }

                        TE_SetupDecal(pos, idx);
                        TE_SendToClient(i);
                    }

                    gI_DecalsPlaced[client]++;
                }
                else
                {
                    PP_PrintToChat(client, "%s%s%s Invalid %sprecache index", gS_ChatStrings.sPrefix, MAP_DECALS_TAG, gS_ChatStrings.sText, gS_ChatStrings.sVariable);
                }
            }
        }

        Decals_OpenDecalMenu(client, decal);
    }
    else if (action == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            Decals_OpenMainDecalMenu(client, ((gI_LastMainMenuIndx[client] + 3) / 7) * 7);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

bool LoadDecals()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "configs/fun/map-decals.cfg");

    if (!FileExists(path))
    {
        LogError("[map-decals] Config file not found: %s", path);
        return false;
    }

    KeyValues kv = new KeyValues("decals");
    if (!kv.ImportFromFile(path))
    {
        LogError("[map-decals] Failed to import config file: %s", path);
        delete kv;
        return false;
    }

    if (gA_Decals == null)
    {
        gA_Decals = new ArrayList(sizeof(decal_data_t));
    }

    if (!kv.GotoFirstSubKey())
    {
        LogError("[map-decals] No decals found in config file");
        delete kv;
        return false;
    }

    int totalDecals = 0;
    do
    {
        decal_data_t decal;
        decal.iIndex = totalDecals;
        decal.aEntries = new ArrayList(sizeof(decal_entry_t));

        kv.GetSectionName(decal.sName, sizeof(decal.sName));
        kv.GetString("flags", decal.sFlags, sizeof(decal.sFlags), "z");

        char baseTexture[PLATFORM_MAX_PATH];
        kv.GetString("texture", baseTexture, sizeof(baseTexture));
        AddVTFToDownloadsTable(baseTexture);

        char sizeKeys[DECAL_SIZES][4] = { "s", "m", "l", "e" };
        char lmKeys[DECAL_SIZES][6] = { "s_lm", "m_lm", "l_lm", "e_lm" };
        char pathBuffer[PLATFORM_MAX_PATH];

        for (int si = 0; si < DECAL_SIZES; si++)
        {
            decal_entry_t decalEntry;
            decalEntry.iPrecacheIndex = 0;
            decalEntry.iPrecacheIndexLM = 0;
            decalEntry.sPath[0] = '\0';
            decalEntry.sPathLM[0] = '\0';

            if (kv.GetString(sizeKeys[si], pathBuffer, sizeof(pathBuffer)) && pathBuffer[0] != '\0')
            {
                strcopy(decalEntry.sPath, sizeof(decalEntry.sPath), pathBuffer);
                decalEntry.iPrecacheIndex = AddVMTToDownloadsTable(decalEntry.sPath);
            }

            if (kv.GetString(lmKeys[si], pathBuffer, sizeof(pathBuffer)) && pathBuffer[0] != '\0')
            {
                strcopy(decalEntry.sPathLM, sizeof(decalEntry.sPathLM), pathBuffer);
                decalEntry.iPrecacheIndexLM = AddVMTToDownloadsTable(decalEntry.sPathLM);
            }

            decal.aEntries.PushArray(decalEntry);
        }

        bool anyValid = false;
        for (int ei = 0; ei < decal.aEntries.Length; ei++)
        {
            decal_entry_t e;
            decal.aEntries.GetArray(ei, e);
            if (strlen(e.sPath) > 0 || strlen(e.sPathLM) > 0)
            {
                anyValid = true;
                break;
            }
        }

        if (anyValid)
        {
            gA_Decals.PushArray(decal);
            totalDecals++;
        }
        else
        {
            LogError("[map-decals] Decal %s has no valid size paths", decal.sName);
            delete decal.aEntries;
        }
    } while (kv.GotoNextKey() && (totalDecals < MAX_DECALS));

    delete kv;

    return true;
}

int AddVMTToDownloadsTable(const char[] vmtPath, bool precache = true)
{
    if (strlen(vmtPath) == 0)
    {
        return 0;
    }

    char fullPath[PLATFORM_MAX_PATH];
    Format(fullPath, sizeof(fullPath), "materials/%s.vmt", vmtPath);
    if (FileExists(fullPath, true))
    {
        AddFileToDownloadsTable(fullPath);
    }
    else
    {
        LogError("[map-decals] VMT file not found: %s", fullPath);
    }

    if (precache)
    {
        Format(fullPath, sizeof(fullPath), "%s.vmt", vmtPath);
        return PrecacheDecal(fullPath, true);
    }

    return 0;
}

void AddVTFToDownloadsTable(const char[] vtfPath)
{
    if (strlen(vtfPath) == 0)
    {
        return;
    }

    char fullPath[PLATFORM_MAX_PATH];
    Format(fullPath, sizeof(fullPath), "materials/%s.vtf", vtfPath);
    if (FileExists(fullPath, true))
    {
        AddFileToDownloadsTable(fullPath);
    }
    else
    {
        LogError("[map-decals] VTF file not found: %s", fullPath);
    }
}


void TE_SetupDecal(const float pos[3], int index, bool world = false)
{
    if (world)
    {
        TE_Start("World Decal");
        TE_WriteVector("m_vecOrigin", pos);
        TE_WriteNum("m_nIndex", index);
    }
    else
    {
        TE_Start("BSP Decal");
        TE_WriteVector("m_vecOrigin", pos);
        TE_WriteNum("m_nEntity", 0);
        TE_WriteNum("m_nIndex", index);
    }
}

stock bool GetClientAimTargetEx(int client, float pos[3], float& dist)
{
    if (!IsValidClient(client))
    {
        return false;
    }

    float angles[3], origin[3];
    GetClientEyeAngles(client, angles);
    GetClientEyePosition(client, origin);

    int entity = -1;
    Handle trace = TR_TraceRayFilterEx(origin, angles, MASK_ALL, RayType_Infinite, Decals_TraceEntityFilter);
    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(pos, trace);
        entity = TR_GetEntityIndex(trace);
    }
    CloseHandle(trace);

    dist = GetVectorDistance(origin, pos);

    return entity >= 0;
}

bool Decals_TraceEntityFilter(int entity, int contentsMask)
{
    return (entity == 0) || (entity > MAXPLAYERS);
}

stock bool IsValidClient(int client, bool bAlive = false)
{
    return (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

bool CheckClientDecalAccess(int client, const char[] requiredFlags)
{
    if (strlen(requiredFlags) == 0)
    {
        return true;
    }

    return Flags_HasForClient(client, MAP_DECALS_PLUGIN, requiredFlags);
}

void DeleteDecals()
{
    if (gA_Decals != null)
    {
        for (int i = 0; i < gA_Decals.Length; i++)
        {
            decal_data_t decal;
            gA_Decals.GetArray(i, decal);

            if (decal.aEntries != null)
            {
                delete decal.aEntries;
            }
        }

        delete gA_Decals;
        gA_Decals = null;
    }
}
