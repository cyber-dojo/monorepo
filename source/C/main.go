// Component C: a tiny Go service stub.
//
// Stands in for a real component. C is a third language/toolchain, to underline
// that the orchestrator does not care what is inside a component, only that it
// honours the trail contract (report an artifact named C, attest C.<name>).
package main

import "fmt"

// greet returns a greeting for the given name.
func greet(name string) string {
	return "C says hello, " + name
}

func main() {
	fmt.Println(greet("world"))
}
