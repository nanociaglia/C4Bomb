#include <sourcemod>
#include <multicolors>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#define PREFIX "{green}[{orange}C4Bomb{green}] {default}%t"

#undef REQUIRE_PLUGIN
#include <zombiereloaded>
#include <store>
#define REQUIRE_PLUGIN

int 	g_iC4Ent = -1,
		g_iMaxUses[MAXPLAYERS+1] = -1;

bool 	g_bGlobalUsed 		= false,
		g_bGC4Used 			= false,
		g_bRestricted 		= false,
		g_bZombieReloaded	= false,
		g_bStoreCredits		= false;
		
Handle 	g_hStoreTimer;

ConVar	g_cEnabled,	g_cVipsOnly, g_cTimerExplosion,	g_cMaxUses,	g_cGlobal, g_cMoney, 
		g_cRestrictRoundStart, g_cBombDamage, g_cBombRadius, g_cTeamKill, g_cTeamRestrict,
		g_cIgniteTime, g_cStoreCredits, g_cPublicMsg;
		
public Plugin myinfo =
{
	name		= 	"Plant C4 Bomb",
	description	= 	"Plant a C4 bomb that kills enemies.",
	author		= 	"Nano",
	version		= 	"1.1",
	url			= 	"http://steamcommunity.com/id/nano2k06"
}

public void OnPluginStart()
{
	g_cEnabled 				= CreateConVar("sm_c4bomb_enabled", 		"1", 		"1 = Enable the plugin | 0 = Disable the plugin (Default 1)");
	g_cVipsOnly 			= CreateConVar("sm_c4bomb_vipsonly", 		"1", 		"1 = Only VIPs (with GENERIC FLAG) can plant a bomb | 0 = Public command (Default 0)");
	g_cTimerExplosion 		= CreateConVar("sm_c4bomb_exp_timer", 		"15", 		"Time in seconds until the bomb explode (Default 15)");
	g_cMaxUses 				= CreateConVar("sm_c4bomb_max_uses", 		"1", 		"Hoy many uses per client to plant the bomb (Default 1)");
	g_cGlobal 				= CreateConVar("sm_c4bomb_global_restict",	"0", 		"1 = Restrict C4 Bomb for everyone after the first plant ever | 0 = Don't restrict the C4 Bomb after the first plant (Default 0)");
	g_cMoney 				= CreateConVar("sm_c4bomb_money", 			"10000", 	"How much money will cost to buy a C4? | 0 = Free C4 (Default 10000)");
	g_cRestrictRoundStart 	= CreateConVar("sm_c4bomb_restrict_start", 	"30", 		"Time in seconds to unlock the C4 Bomb after round start | 0 = Disable (Default 30)");
	g_cBombDamage 			= CreateConVar("sm_c4bomb_bomb_damage", 	"5000", 	"Damage of the bomb (Default 5000)");
	g_cBombRadius 			= CreateConVar("sm_c4bomb_bomb_radius", 	"600", 		"Radius of the bomb explosion (Default 600)");
	g_cTeamKill 			= CreateConVar("sm_c4bomb_team_kill", 		"1", 		"0 = Bomb will kill team mates | 1 = Bomb won't kill team mates (Default 1) | TIP: If 0, C4 on explode won't give frags as kill");
	g_cTeamRestrict 		= CreateConVar("sm_c4bomb_team_restrict", 	"2", 		"1 = All teams | 2 = Only CTs | 3 = Only Terrorist (Default 1)");
	g_cIgniteTime			= CreateConVar("sm_c4bomb_ignite_time", 	"7", 		"Time in seconds to ignite enemies | 0 = Disabled (Default 7)");
	g_cStoreCredits			= CreateConVar("sm_c4bomb_store_credits", 	"0", 		"Store credits to buy C4 (Default 0)");
	g_cPublicMsg			= CreateConVar("sm_c4bomb_plant_message", 	"1", 		"Print a public message when someone plant a bomb? | 1 = Enabled | 0 = Disabled (Default 1)");

	RegConsoleCmd("sm_c4", Command_C4);
	RegConsoleCmd("sm_bomb", Command_C4);
	RegConsoleCmd("sm_c4bomb", Command_C4);
	
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("round_start", Event_OnRoundStart);

	LoadTranslations("c4bomb.phrases");
	AutoExecConfig(true, "c4bomb");
}

public void OnMapStart()
{
	PrecacheSound("weapons/c4/c4_explode1.wav", true);
	PrecacheSound("weapons/c4/c4_beep3.wav", true);
	PrecacheSound("weapons/c4/c4_initiate.wav", true);
	PrecacheModel("weapons/w_c4_planted.mdl", true);
}

public void OnAllPluginsLoaded()
{
	g_bZombieReloaded	= LibraryExists("zombiereloaded");
	g_bStoreCredits		= LibraryExists("store");
}
 
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_bZombieReloaded = true;
	}
	else if (StrEqual(name, "store"))
	{
		g_bStoreCredits = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_bZombieReloaded = false;
	}
	else if (StrEqual(name, "store"))
	{
		g_bStoreCredits = false;
	}
}

public void OnClientPutInServer(int client) 
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage); 
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("ZR_IsClientZombie");
	MarkNativeAsOptional("Store_GetClientCredits");
	MarkNativeAsOptional("Store_SetClientCredits");
	return APLRes_Success;
}

//---------------------------------------
// Purpose: Actions
//---------------------------------------

public Action Event_OnRoundEnd(Event event, char[] name, bool dontBroadcast)
{
	g_bGC4Used = false;
	g_bGlobalUsed = false;
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (IsClientInGame(i))
		{
			g_iMaxUses[i] = false;
		}
	}
}

public Action Event_OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
	if(g_hStoreTimer != INVALID_HANDLE)
	{
		KillTimer(g_hStoreTimer);
		g_hStoreTimer = INVALID_HANDLE;
	}

	if(g_cRestrictRoundStart.IntValue > 0)
	{
		g_bRestricted = true;
		g_hStoreTimer = CreateTimer(g_cRestrictRoundStart.FloatValue, Timer_UnlockBomb);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) 
{
	if(g_cIgniteTime.IntValue >= 1)
	{
		char sExplosion[32];
		GetEntityClassname(inflictor, sExplosion, sizeof(sExplosion));

		if (StrContains(sExplosion, "env_explosion") != -1)
		{
			if(g_bZombieReloaded)
			{
				if(!ZR_IsClientZombie(victim))
				{
					IgniteEntity(victim, g_cIgniteTime.FloatValue);
					return Plugin_Changed;
				}
			}
			else
			{
				IgniteEntity(victim, g_cIgniteTime.FloatValue);
				return Plugin_Changed;
			}
		}
	}

	return Plugin_Continue;
}

//---------------------------------------
// Purpose: Command
//---------------------------------------

public Action Command_C4(int client, int args)
{
	int iMoney		= GetEntProp(client, Prop_Send, "m_iAccount");
	int iMaxUses	= g_cMaxUses.IntValue;
	int iCost		= g_cMoney.IntValue;

	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		CPrintToChat(client, PREFIX, "ALIVE");
		return Plugin_Handled;
	}

	if(!g_cEnabled.BoolValue)
	{
		CPrintToChat(client, PREFIX, "DISABLED");
		return Plugin_Handled;
	}

	if(g_cVipsOnly.IntValue >= 1)
	{
		if(!CheckCommandAccess(client, "sm_c4bomb_override", ADMFLAG_GENERIC))
		{
			CPrintToChat(client, PREFIX, "VIPS_ONLY");
			return Plugin_Handled;
		}
	}

	if(g_cRestrictRoundStart.IntValue > 0)
	{
		if(g_bRestricted)
		{
			CPrintToChat(client, PREFIX, "ROUND_START");
			return Plugin_Handled;
		}
	}

	if(g_iMaxUses[client] >= iMaxUses)
	{
		CPrintToChat(client, PREFIX, "MAX_USES", g_iMaxUses[client]);
		return Plugin_Handled;
	}

	if(g_cGlobal.BoolValue)
	{
		if(g_bGlobalUsed)
		{
			CPrintToChat(client, PREFIX, "GLOBAL_USED");
			return Plugin_Handled;
		}
	}

	if(iMoney < iCost)
	{
		CPrintToChat(client, PREFIX, "NOT_ENOUGH_MONEY", iCost);
		return Plugin_Handled;
	}

	if(!(GetEntityFlags(client) & FL_ONGROUND))
	{
		CPrintToChat(client, PREFIX, "ON_GROUND");
		return Plugin_Handled;
	}

	if(g_bGC4Used)
	{
		CPrintToChat(client, PREFIX, "USED");
		return Plugin_Handled;
	}

	if(g_bZombieReloaded)
	{
		if(ZR_IsClientZombie(client))
		{
			CPrintToChat(client, PREFIX, "HUMANS");
			return Plugin_Handled;
		}
	}

	if(g_bStoreCredits)
	{
		if(g_cStoreCredits.IntValue >= 1)
		{
			if(Store_GetClientCredits(client) < GetConVarInt(g_cStoreCredits))
			{
				CPrintToChat(client, PREFIX, "STORE", GetConVarInt(g_cStoreCredits))
				return Plugin_Handled;
			}
		}
	}

	if(!g_bZombieReloaded)
	{
		if(g_cTeamRestrict.IntValue >= 2)
		{
			if(GetClientTeam(client) == GetConVarInt(g_cTeamRestrict))
			{
				CPrintToChat(client, PREFIX, "TEAM");
				return Plugin_Handled;
			}
		}
	}

	SpawnC4(client);
	g_bGlobalUsed = true;
	g_bGC4Used = true;
	g_iMaxUses[client]++;
	SetEntProp(client, Prop_Send, "m_iAccount", iMoney - iCost);
	
	if(g_cStoreCredits.IntValue >= 1)
	{
		Store_SetClientCredits(client, Store_GetClientCredits(client) - GetConVarInt(g_cStoreCredits));
	}

	if(g_cPublicMsg.IntValue == 1)
	{
		CPrintToChatAll(PREFIX, "PLANTED", client, g_cTimerExplosion.IntValue);
	}

	float fEyePos[3];
	GetClientEyePosition(client, fEyePos);
	EmitAmbientSound("weapons/c4/c4_initiate.wav", fEyePos, client);

	CreateTimer(1.0, Timer_Beep, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(g_cTimerExplosion.FloatValue, Timer_Boom, GetClientUserId(client));
	return Plugin_Handled;
}

//---------------------------------------
// Purpose: Timers
//---------------------------------------

public Action Timer_UnlockBomb(Handle timer)
{
	g_hStoreTimer = INVALID_HANDLE;
	g_bRestricted = false;
}

public Action Timer_Beep(Handle timer)
{
	static int iBeep = 0;
	int m_iEnt = EntRefToEntIndex(g_iC4Ent);
 
	if (iBeep > g_cTimerExplosion.IntValue) 
	{
		iBeep = 0;
		return Plugin_Stop;
	}
	
	if(IsValidEntity(m_iEnt))
	{
		float fC4Possition[3];
		GetEntPropVector(m_iEnt, Prop_Send, "m_vecOrigin", fC4Possition);
		EmitAmbientSound("weapons/c4/c4_beep3.wav", fC4Possition, m_iEnt);
	}
	iBeep++;

	return Plugin_Continue;
}

public Action Timer_Boom(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client) 
	{
		return;
	}

	int m_iEnt = EntRefToEntIndex(g_iC4Ent);
	int iExplIndex = CreateEntityByName("env_explosion");
	int iParticleIndex = CreateEntityByName("info_particle_system");

	if(IsValidEntity(m_iEnt))
	{
		float fExploOrigin[3];
		GetEntPropVector(m_iEnt, Prop_Send, "m_vecOrigin", fExploOrigin);

		if (iExplIndex != -1 && iParticleIndex != -1)
		{
			DispatchKeyValue(iParticleIndex, "effect_name", "explosion_c4_500_fallback");
		
			SetEntProp(iExplIndex, Prop_Data, "m_spawnflags", 16384);
			SetEntProp(iExplIndex, Prop_Data, "m_iMagnitude", GetConVarInt(g_cBombDamage));
			SetEntProp(iExplIndex, Prop_Data, "m_iRadiusOverride", GetConVarInt(g_cBombRadius));
		
			TeleportEntity(iExplIndex, fExploOrigin, NULL_VECTOR, NULL_VECTOR);
			TeleportEntity(iParticleIndex, fExploOrigin, NULL_VECTOR, NULL_VECTOR);
			
			DispatchSpawn(iExplIndex);
			DispatchSpawn(iParticleIndex);

			ActivateEntity(iExplIndex);
			ActivateEntity(iParticleIndex);
			
			if(g_cTeamKill.IntValue >= 1)
			{
				SetEntPropEnt(iExplIndex, Prop_Send, "m_hOwnerEntity", client);
			}

			EmitSoundToAll("weapons/c4/c4_explode1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);

			AcceptEntityInput(iExplIndex, "Explode");
			AcceptEntityInput(iParticleIndex, "Start");
		}
	}

	if (g_iC4Ent != INVALID_ENT_REFERENCE)
	{
		if(IsValidEntity(m_iEnt))
			AcceptEntityInput(m_iEnt, "Kill");
		g_iC4Ent = INVALID_ENT_REFERENCE;
	}

	g_bGC4Used = false;
}

//---------------------------------------
// Purpose: Spawn C4 bomb
//---------------------------------------

void SpawnC4(int client) 
{
	g_iC4Ent = EntIndexToEntRef(CreateEntityByName("prop_dynamic_override"))
	int m_iEnt = EntRefToEntIndex(g_iC4Ent);

	DispatchKeyValue(m_iEnt, "model", "models/weapons/w_c4_planted.mdl"); 
	DispatchKeyValue(m_iEnt, "spawnflags", "256"); 
	DispatchKeyValue(m_iEnt, "solid", "0");
	DispatchKeyValue(m_iEnt, "modelscale", "2.0");

	float fPosition[3];
	GetClientEyePosition(client, fPosition);
	fPosition[2] -= 65.0;
 
	DispatchSpawn(m_iEnt); 

	TeleportEntity(m_iEnt, fPosition, NULL_VECTOR, NULL_VECTOR);
}