using System;
using System.IO;

namespace OpenSkin
{
    internal enum Skin { DragonCodex, EmeraldAwakening }

    internal static class Skins
    {
        internal static readonly Skin[] All = { Skin.DragonCodex, Skin.EmeraldAwakening };
        internal static string Title(this Skin skin) => skin == Skin.DragonCodex ? "Dragon Codex" : "翡翠觉醒";
        internal static string Asset(this Skin skin, string name) =>
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, skin.ToString(), name);
    }
}
