# Component dashboard: a tiny Ruby service stub.
#
# Stands in for a real component. dashboard is intentionally a different language and
# toolchain from web to show that each component keeps its own bespoke pipeline.

# Return a greeting for the given name.
def greet(name)
  "dashboard says hello, #{name}"
end

puts greet("world") if __FILE__ == $PROGRAM_NAME
