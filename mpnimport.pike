/* Generate slides.html with hymn texts.

By default, will read from MPN - see below. Otherwise, provide a series of hymn refs
on the command line:
$ pike mpnimport RCM 160 RCM 212 PP 11
To see which hymn refs are available, "pike mpnimport list". Follow that format for
best results.

1) Read current status of MPN
2) Locate the "interesting bit"
3) Pull hymns from the git history
   git show `git log -S '<h3>Rej 246: ' -1 --pretty=%H`^:slides.html
   sscanf(data, "%*s<h3>Rej 246: %s</cite>", string hymn);
   If none, create stub (including empty citation and two verses)
4) Handle PP numberless:
   git show `git log -S '<h3>PP [0-9]*: Title' --pickaxe-regex -1 --pretty=%H`^:slides.html
5) Update MPN if any PPs got their numbers added (require auth? or use pseudo-auth of 192.168?)
6) Handle title conflicts somehow

Interesting lines:
Hymn [PP] By Faith
-- see #4 and #5
Hymn [R540] Jesus, I Am Trusting, Trusting
-- see #3
Opening Prayer (BO)
-- nothing
Announcements (JA)
-- nothing
Bible reading: Matthew 11:1-19 (page 688) (LO)
-- emit <address> block
Offering [] (BO)
-- nothing
Prayer for our church and the world (JA)
-- nothing
Hymn [tune - R474] Put all your trust in God
-- probably disallow in favour of: Hymn [PP] Put all your trust in God (to R474)
-- parenthesized parts get dropped
Bible reading: Matthew 11:20-30 (page 689) (BO)
-- address as above
Sermon: “HELP FOR THE WEAK AND DOUBTING” (BO) 
-- ????? Stubs??? Something from sermon outline???
Hymn [R405] Not What I Am, O Lord, But What You Are
-- #3 above. Note the capitalization inconsistencies. Resolve?
Benediction (BO)
-- nothing
Exit []
-- nothing

TODO: Scripture references (<address> blocks) to get actual content (<aside>???)
-- not too hard if we're willing to change version, else VERY hard due to copyright
-- https://getbible.net/api offers several English versions but not NIV
-- and hey, we could offer any number of non-English versions too.....
-- could sync up with https://github.com/Rosuav/niv84 but then we do the work ourselves

*/
string current = utf8_to_string(Stdio.read_file("slides.html"));
string sermonnotes = "";

string mpn_Welcome = #"<section data-bg=\"SolidDirt.png\">
<h3><img src=\"Cross.png\"> Ashburton Presbyterian Church</h3>
<p></p>
<h1>Welcome</h1>
<footer>Finding solid ground in Christ</footer>
</section>";
string mpn_Opening = ""; //Opening Prayer
string mpn_Prayer = "";
string mpn_Announcements = "";
string mpn_Offering = "";
string mpn_The = ""; //The Lord's Supper. Probably should make this a function that verifies.
string mpn_Benediction = "";
string mpn_Exit = "";

string mpn_Hymn(string line)
{
	sscanf(line, "Hymn [%s] %s", string id, string titlehint);
	if (sscanf(id, "R%d", int rej) && rej) id = "Rej " + rej;
	if (id == "PP")
	{
		//Barry hack. Find any previous usage of "PP %d:" with a matching title.
		foreach (current/"\n", string line) if (sscanf(line, "<h3>PP %d: %s</h3>", int pp, string title))
			if (lower_case(title) == lower_case(titlehint)) id = "PP " + pp;
		if (id == "PP") //Didn't find one in the current file. Search history.
		{
			//We use git's regex handling, here, so hopefully there won't be any
			//square brackets or anything in the title. (Dots aren't a problem -
			//a dot matches a dot just fine, and it's unlikely to have a false pos.)
			string sha1 = String.trim_all_whites(Process.run(({
				"git", "log", "-S", "<h3>PP [0-9]*: " + titlehint, "--pickaxe-regex", "-i", "-1", "--pretty=%H"
			}))->stdout);
			if (sha1)
			{
				string text = utf8_to_string(Process.run(({"git", "show", sha1+"^:slides.html"}))->stdout);
				foreach (text/"\n", string line) if (sscanf(line, "<h3>PP %d: %s</h3>", int pp, string title))
					if (lower_case(title) == lower_case(titlehint)) id = "PP " + pp;
			}
			if (id == "PP") id = "PP" + hash_value(titlehint); //Big long number :)
			//For simplicity, just fall through.
		}
	}
	//See if a hymn with that ID is in the current file. The git check
	//below won't correctly handle that case, so let's special-case it
	//for safety and simplicity.
	if (has_value(current, "<h3>" + id + ": "))
	{
		sscanf(current, "%*s<h3>"+id+": %s</h3>%s</cite>", string title, string body);
		//TODO: Handle title/titlehint mismatches (not counting whitespace)
		if (!title || !body) error("Unable to parse current hymn: %O\n", line);
		return sprintf("<section>\n<h3>%s: %s</h3>%s</cite>\n</section>", id, title, body);
	}
	//Okay, it wasn't found. Locate the most recent commit that adds or removes
	//the string "<h3>HymnID: ". It'll be a removal, since that ID doesn't occur
	//in the current file.
	string sha1 = String.trim_all_whites(Process.run(({
		"git", "log", "-S", sprintf("<h3>%s: ", id), "-1", "--pretty=%H"
	}))->stdout);
	if (sha1 == "")
	{
		//No such hymn found. Create a stub.
		return sprintf(#"<section>
<h3>%s: %s</h3>

</section>
<section>

<cite>\xA9 1900-2000 Someone, Somewhere</cite>
</section>", id, titlehint);
	}
	//Awesome! We have a SHA1 that *removed* this hymn ID.
	//Most likely, it removed the whole hymn text, but we don't care. All we
	//want is the text that was there *just before* the removal, which can be
	//referenced as 142857^ and the file name. (I love git!)
	string oldtext = utf8_to_string(Process.run(({"git", "show", sha1 + "^:slides.html"}))->stdout);
	//TODO: Dedup
	if (has_value(oldtext, "<h3>" + id + ": "))
	{
		sscanf(oldtext, "%*s<h3>"+id+": %s</h3>%s</cite>", string title, string body);
		//TODO: Handle title/titlehint mismatches (not counting whitespace)
		if (!title || !body) error("Unable to parse hymn from %s: %O\n", sha1, line);
		return sprintf("<section>\n<h3>%s: %s</h3>%s</cite>\n</section>", id, title, body);
	}
	error("Hymn not found in %s: %O\n", sha1, line);
}

string mpn_Bible(string line)
{
	sscanf(line, "Bible reading: %s (page %d)", string ref, int page);
	if (!ref || !page) error("Unable to parse Scripture reading: %O\n", line);
	return sprintf("<section><address>%s\npage %d</address></section>", ref, page);
}

string mpn_Sermon(string line)
{
	sscanf(line, "Sermon: %s (", string title);
	return "<section>\n" + title + "\n" + sermonnotes + "\n</section>";
}

int main(int argc, array(string) argv)
{
	if (argc > 1 && lower_case(argv[1]) == "list")
	{
		mapping(string:mapping(int:string)) titles = ([]);
		string text = current;
		while (sscanf(text, "%*s<h3>%s</h3>%s", string hdr, text) == 3)
			if (sscanf(hdr, "%[A-Za-z] %d: %s", string book, int num, string title) == 3)
			{
				if (!titles[book]) titles[book] = ([]);
				if (!titles[book][num]) titles[book][num] = title;
			}
		foreach (String.trim_all_whites(Process.run(({
			"git", "log", "-S", "<h3>[A-Za-z0-9 ]+: ", "--pickaxe-regex", "--pretty=%H"
		}))->stdout)/"\n", string sha1)
		{
			string text = utf8_to_string(Process.run(({"git", "show", sha1 + "^:slides.html"}))->stdout);
			while (sscanf(text, "%*s<h3>%s</h3>%s", string hdr, text) == 3)
				if (sscanf(hdr, "%[A-Za-z] %d: %s", string book, int num, string title) == 3)
				{
					if (!titles[book]) titles[book] = ([]);
					if (!titles[book][num]) titles[book][num] = title;
				}
		}
		foreach (titles; string book; mapping hymns)
			foreach (sort(indices(hymns)), int num)
				write("%s %d: %s\n", book, num, hymns[num]);
		return 0;
	}
	//Some of the 'git log' commands could become majorly messed up if certain
	//types of edit have been made to slides.html since the last commit. So for
	//simplicity, just do a quick check against HEAD and die early.
	string HEAD = utf8_to_string(Process.run(({"git", "show", "HEAD:slides.html"}))->stdout);
	if (current != HEAD) exit(1, "For safety, it is forbidden to run this with uncommitted changes to slides.html.\n");

	sscanf(current, "%s<section", string header);
	string footer = (current / "</section>")[-1];

	if (argc > 1 && (argc&1))
	{
		array(string) parts = ({ });
		foreach (argv[1..]/2, [string book, string num])
			parts += ({mpn_Hymn(sprintf("Hymn [%s %s] ...", book, num))});
		Stdio.write_file("slides.html", string_to_utf8(header + (parts-({""}))*"\n" + footer));
		Process.create_process(({"git", "commit", "slides.html", "-mBuild slides for specific hymns"}))->wait();
		return 0;
	}

	string mpn = Protocols.HTTP.get_url_data("http://gideon.kepl.com.au:8000/mpn/sundaymusic.0");
	if (!mpn) exit(1, "Unable to retrieve MPN - are you offline?\n");
	sscanf(utf8_to_string(mpn), "%d\0%s", int mpnindex, mpn); //Trim off the indexing headers

	//Assume that MPN consists of several paragraphs, and pick the first one with a hymn.
	string service;
	foreach (mpn/"\n\n", string para)
		if (has_value(para, "\nHymn [")) service = para;
		else if (service && sermonnotes=="") sermonnotes = para; //Not used for much
	if (!service) exit(1, "Unable to find Order of Service paragraph in MPN.\n");

	array(string) parts = ({ });
	foreach (service/"\n", string line)
	{
		sscanf(line, "%[A-Za-z]", string word);
		string|function handler = this["mpn_" + word];
		if (!handler) exit(1, "ERROR: Unknown line %O\n", line);
		parts += ({stringp(handler) ? handler : handler(line)});
	}

	//If we get here, every line was recognized and accepted without error.
	Stdio.write_file("slides.html", string_to_utf8(header + (parts-({""}))*"\n" + footer));
	Process.create_process(({"git", "commit", "slides.html", sprintf("-mUpdate slides from MPN #%d", mpnindex)}))->wait();
}