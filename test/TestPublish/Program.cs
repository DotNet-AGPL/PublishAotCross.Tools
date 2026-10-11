using System;

Console.WriteLine("Hello World");

// Wait for a key only when attached to an interactive console (local runs).
// In CI / redirected input, Console.ReadKey() throws.
if (!Console.IsInputRedirected)
{
    Console.ReadKey();
}
