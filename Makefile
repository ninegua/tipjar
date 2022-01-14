src/tipjar_assets/assets/faq.html: FAQ.md
	tail -n"$$(($$(wc -l FAQ.md|cut -d\  -f1) - 1))" $< | \
		pandoc --css=https://cdn.simplecss.org/simple.min.css --toc --toc-depth=6 \
		--template=template.html -f markdown -t html --shift-heading-level-by=3 > $@

clean:
	rm src/tipjar_assets/assets/faq.html
