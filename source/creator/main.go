// Component creator: a tiny Go service stub.
//
// Stands in for a real component. creator is a third language/toolchain, to underline
// that the orchestrator does not care what is inside a component, only that it
// honours the trail contract (report an artifact named creator, attest creator.<name>).
package main

import "fmt"

// greet returns a greeting for the given name.
func greet(name string) string {
	return "creator says hello, " + name
}

func main() {
	fmt.Println(greet("world"))
}
