.PHONY: all

TARGET := pjproject-symbol-rewrite.h

all: $(TARGET)

$(TARGET): unexported-symbols.def
	./gen-prefix-header.sh < $< > $@.new.$$PPID
	mv $@.new.$$PPID $@

clean:
	rm -f $(TARGET) $(TARGET).new.*
