
IMAGES := $(shell grep -r "path: /images/" _posts/ | sed -n 's/.*path: \/images\/\([^[:space:]]*\).*/\1/p' | sort -u)

# Convert to thumbnail paths
THUMBS := $(addprefix images/thumbs/,$(IMAGES))

images/thumbs/%: images/%
	@echo "Processing: $<"
	convert "$<" -resize 305x229 -background white -gravity center -extent 305x229 -quality 80 "$@"

all:	$(THUMBS)
	bundle exec -- jekyll serve --port 8001

build:
	bundle exec -- jekyll build

