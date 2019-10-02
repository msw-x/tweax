import sublime, sublime_plugin


class MswInsertTabCommand(sublime_plugin.TextCommand):
	tab_size = 4

	def run(self, edit, next = True):
		view = self.view

		est_vcol = None
		max_end_word = 0
		for sel in view.sel():
			row, col = view.rowcol(sel.begin())
			s        = self.line_str(view, row)
			vcol     = self.view_col(s, col   )

			if len( view.sel() ) == 1:
				if 0 < row:
					ps       = self.line_str     (view, row - 1)
					est_vcol = self.next_word_col(ps, vcol     )
			else:
				a = self.first_after_word_col(s, vcol, col)
				if max_end_word < a[0]:
					max_end_word = a[0]
					est_vcol     = a[0] + 1

		new_sel = []
		for sel in view.sel():
			processed = False

			row, col = view.rowcol(sel.begin())
			s    = self.line_str(view, row)
			vcol = self.view_col(s, col   )
			a    = self.first_after_word_col(s, vcol, col)
			b    = self.next_non_space_col  (s, vcol, col)

			if est_vcol  and  a[0] != 0:
				dist = est_vcol - a[0]
				pt = sel.begin() - ( col - a[1] )
				rgn = sublime.Region( pt, pt + b[1] - a[1] )

				spaces = ""
				for i in range( dist ):
					spaces += " "

				if rgn.begin() == rgn.end():
					view.insert(edit, rgn.begin(), spaces)
				else:
					if view.substr(rgn) != spaces:
						view.replace(edit, rgn, spaces)

				sel = sublime.Region(pt + dist)
				processed = True

			if not processed:
				view.insert(edit, sel.begin(), "\t")
				sel = sublime.Region(sel.begin() + 1, sel.end() + 1)

			new_sel.append(sel)

		view.sel().clear()
		view.sel().add_all(new_sel)

	def line_str(self, view, row):
		return view.substr(view.line(view.text_point(row, 0)))

	def view_col(self, s, col):
		vcol = 0
		for i in range( col ):
			if s[i] == '\t':
				vcol = int((vcol + self.tab_size) / self.tab_size) * self.tab_size
			else:
				vcol += 1
		return vcol

	def next_non_space_col(self, s, vcol, p):
		while p < len(s):
			if s[p] == ' ':
				vcol += 1
			elif s[p] == '\t':
				vcol = int((vcol + self.tab_size) / self.tab_size) * self.tab_size

			else:
				break

			p += 1
		return (vcol, p)

	def first_after_word_col(self, s, vcol, p):
		while 0 < p and (s[p-1] == ' ' or s[p-1] == '\t') :
			p -= 1
		return (self.view_col( s, p ), p)

	def next_word_col(self, s, s_vcol):
		p = 0
		vcol = 0
		while vcol < s_vcol  and  p < len(s):
			if s[p] == '\t':
				vcol = int((vcol + self.tab_size) / self.tab_size) * self.tab_size
			else:
				vcol += 1
			p += 1

		if vcol < s_vcol:
			return None

		while p < len(s) :
			if s[p] == ' ' or s[p] == '\t':
				break
			p += 1
			vcol += 1

		vcol, p = self.next_non_space_col(s, vcol, p)

		if p < len(s):
			return vcol
		return None
