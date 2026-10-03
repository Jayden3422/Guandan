using System;
using System.IO;
using System.Text;
using MoonSharp.Interpreter;

// Runs Lua files in MoonSharp, the Lua interpreter Tabletop Simulator uses, in one shared environment.
// Usage:  harness <game's Managed folder> <lua file> ...
class Program
{
    static int Main(string[] args)
    {
        var script = new Script();
        script.Options.DebugPrint = s => Console.WriteLine(s);
        try
        {
            script.Globals["Vector"] = script.DoString(VectorScript(args[0]), null, "Vector");
            for (int i = 1; i < args.Length; i++)
            {
                script.DoString(File.ReadAllText(args[i]), null, Path.GetFileName(args[i]));
            }
        }
        catch (InterpreterException e)
        {
            Console.WriteLine("LUA ERROR: " + e.DecoratedMessage);
            return 1;
        }
        return 0;
    }

    // The Vector class the game gives every script is Lua source kept as a string in the game's own assembly.
    // It is read straight from the file, so the assembly does not have to be loaded.
    static string VectorScript(string managedFolder)
    {
        const string start = "local Vector = {}";
        const string end = "\r\nreturn Vector\r\n";

        byte[] bytes = File.ReadAllBytes(Path.Combine(managedFolder, "Assembly-CSharp.dll"));

        // The string is UTF-16, at an even or odd offset in the file.
        for (int offset = 0; offset < 2; offset++)
        {
            string text = Encoding.Unicode.GetString(bytes, offset, (bytes.Length - offset) / 2 * 2);
            int from = text.IndexOf(start, StringComparison.Ordinal);
            if (from < 0)
            {
                continue;
            }
            int to = text.IndexOf(end, from, StringComparison.Ordinal);
            if (to >= 0)
            {
                return text.Substring(from, to + end.Length - from);
            }
        }

        throw new InvalidOperationException("The Vector script was not found in Assembly-CSharp.dll.");
    }
}
