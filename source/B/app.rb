# Component B: a tiny Ruby service stub.
#
# Stands in for a real component. B is intentionally a different language and
# toolchain from A to show that each component keeps its own bespoke pipeline.

# Return a greeting for the given name.
def greet(name)
  "B says hello, #{name}"
end

puts greet("world") if __FILE__ == $PROGRAM_NAME
