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
string sermondate = "", service = 0, sermonnotes = "";

string mpn_Welcome = #"<section class=\"welcome\" data-bg=\"SolidDirt.png\">
<h3><img src=\"Cross.png\"> Ashburton Presbyterian Church</h3>
<p></p>
<p></p>
<p></p>
<h1>Welcome</h1>
<footer>Finding solid ground in Christ</footer>
</section>";
string mpn_Opening = ""; //Opening Prayer
string mpn_Prayer = "";
string mpn_Announcements = "";
string mpn_Church = ""; //Special case - Church Update (might never be used again, but whatevs)
string mpn_Children = ""; //No automatic slides for the children's talk. If there are any, add them manually.
string mpn_Offering = "";
string mpn_The = ""; //The Lord's Supper. Probably should make this a function that verifies.
string mpn_Communion = "";
string mpn_Mission = "";
string mpn_Benediction = "";
string mpn_Exit = "";

string mpn_Hymn(string line)
{
	sscanf(line, "Hymn%*[:] [%s] %s", string id, string titlehint);
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
				"git", "log", "-S", "<h3>PP [0-9]*: " + titlehint, "--pickaxe-regex", "-i", "-1", "--pretty=%H", "slides.html"
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
		"git", "log", "-S", sprintf("<h3>%s: ", id), "-1", "--pretty=%H", "slides.html"
	}))->stdout);
	if (sha1 == "")
	{
		//No such hymn found. Create a stub.
		string copy = "\xA9 1900-2000 Someone, Somewhere";
		//Rejoice! hymns are likely to be copyright to the Pressy Church.
		if (has_prefix(id, "Rej ")) copy = "[Author Name], Rejoice! \xA9 Presbyterian Church Australia";
		return sprintf(#"<section>
<h3>%s: %s</h3>

</section>
<section>

<cite>%s</cite>
</section>", id, titlehint, copy);
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
	sscanf(line, "Bible reading: %s (page%[s] %[-, 0-9])", string ref, string plural, string page);
	if (!ref || !page) error("Unable to parse Scripture reading: %O\n", line);
	return sprintf("<section><address>%s\npage%s %s</address></section>", ref, plural, page);
}

string mpn_Sermon(string line)
{
	sscanf(line, "Sermon: %s (%s)", string title, string person);
	person = (["Barry": "Barry Oakes"])[person] || person; //Un-shorthand where appropriate
	//Attempt to update the sermon notes and order of service for the web site
	string website = "../AshyPC.github.io"; //TODO maybe: allow multiple directory names
	if (file_stat(website + "/Service_Weekly"))
	{
		//Generate an order of service from the main MPN block.
		array(string) lines = service / "\n";
		//Go through the lines and bold the beginnings of (most of) them
		//Also, Bible readings get enumerated.
		int reading = 0;
		foreach (lines; int i; string line)
		{
			if (sscanf(line, "Bible reading: %s", string info) && info)
				lines[i] = sprintf("**Bible reading %d:** %s", ++reading, info);
			else if (sscanf(line, "%s: %s", string prefix, string rest) && rest)
				lines[i] = sprintf("**%s:** %s", prefix, rest);
			else if (sscanf(line, "Hymn [%s] %s", string ref, string rest) && rest)
				lines[i] = sprintf("**Hymn [%s]** %s", ref, rest);
			else if (sscanf(line, "%s (%s", string main, string paren) && paren)
				lines[i] = sprintf("**%s** (%s", main, paren);
		}
		Stdio.write_file(website + "/Service_Weekly/Order_Of_Service.md", string_to_utf8(sprintf(#"---
layout: oos
title: Order of Service
---
### Order of Service %s
### %s

%{%s

%}**Exit**
", sermondate, person, lines)));
		//Next up: Generate the sermon notes from the paragraph below the main block.
		lines = sermonnotes / "\n";
		//Again, we preprocess; in this case, to mark the intro and conc as getting
		//less space (by bulleting them), while guarding the digits against listification.
		foreach (lines; int i; string line)
			if (sscanf(line, "%d. %s", int point, string txt) && txt)
				lines[i] = sprintf("%d\\. %s", point, txt);
			else
				lines[i] = "* " + line;
		//The first line becomes a heading, not a bullet point.
		lines[0] = "###" + lines[0][1..];
		Stdio.write_file(website + "/Service_Weekly/Sermon_Notes.md", string_to_utf8(sprintf(#"---
layout: oos
title: Sermon Notes
---
### Ashburton Presbyterian Church %s

### %s
%{
%s
%}", sermondate, person, lines)));
		Process.create_process(({"git", "-C", website, "commit",
			"Service_Weekly/Order_Of_Service.md", "Service_Weekly/Sermon_Notes.md",
			"-mUpdate order of service and sermon notes from MPN"}))->wait();
	}
	//Nothing actually gets added to the slides.
	return "";
}

string mpn_Video(string line)
{
	sscanf(line, "Video%*[ :-]%s", string title);
	sscanf(title, "%s (%*[A-Z])", title); //Trim off a person tag
	return #"<section class=black>
<video controls>
<source src=\"...\" alt=\"" + Protocols.HTTP.quoted_string_encode(title) + #"\">
</video>
</section>";
}

int main(int argc, array(string) argv)
{
	if (argc > 1 && lower_case(argv[1]) == "list")
	{
		mapping(string:mapping(int:array(string))) titles = ([]);
		//The current state is represented by the most recent commit that changed slides.html.
		string hashes = Process.run(({"git", "log", "-1", "--pretty=%H", "slides.html"}))->stdout;
		//Previous states are those which add/remove appropriately-formatted heading tags.
		hashes += Process.run(({
			//Note that the "pretty" format sticks a caret after the hash. We'll use that :)
			//The first hash (for the most recent state) is what we want; the others, go one back.
			"git", "log", "-G", "<h3>[A-Za-z0-9 ]+: ", "--pretty=%H^", "slides.html"
		}))->stdout;
		int booklen, titlelen, datelen;
		foreach (String.trim_all_whites(hashes)/"\n", string sha1)
		{
			//TODO: Have different options governing the time display.
			sscanf(Process.run(({"git", "show", sha1, "--pretty=%H %ai %ar"}))->stdout,
				"%s %s %s %s %s\n", string creator, string date, string time, string tz, string relative);
			string text = utf8_to_string(Process.run(({"git", "show", sha1 + ":slides.html"}))->stdout);
			while (sscanf(text, "%*s<h3>%s</h3>%s", string hdr, text) == 3)
				if (sscanf(hdr, "%[A-Za-z] %d: %s", string book, int num, string title) == 3)
				{
					booklen = max(booklen, sizeof(book));
					titlelen = max(titlelen, sizeof(title));
					datelen = max(datelen, sizeof(relative));
					if (!titles[book]) titles[book] = ([]);
					if (!titles[book][num]) titles[book][num] = ({title, relative});
				}
		}
		int need = booklen + titlelen + datelen + 7; //Assumes three digits for the hymn number. TODO: Don't assume.
		catch {if (Stdio.stdin->tcgetattr()->columns >= need)
		{
			//Use a tabular layout, since we have the room. (If we can't figure out whether we have
			//room or not, assume we don't. We could assume 80 columns, maybe, but just don't.)
			foreach (titles; string book; mapping hymns)
				foreach (sort(indices(hymns)), int num)
					write("%*s %3d %-*s %s\n", booklen, book, num, titlelen, @hymns[num]);
			return 0;
		}};
		foreach (titles; string book; mapping hymns)
			foreach (sort(indices(hymns)), int num)
				write("%s %d: %s [%s]\n", book, num, @hymns[num]);
		return 0;
	}
	//Some of the 'git log' commands could become majorly messed up if certain
	//types of edit have been made to slides.html since the last commit. So for
	//simplicity, just do a quick check against HEAD and die early.
	string HEAD = utf8_to_string(Process.run(({"git", "show", "HEAD:slides.html"}))->stdout);
	if (current != HEAD) exit(1, "For safety, it is forbidden to run this with uncommitted changes to slides.html.\n");

	sscanf(current, "%s<section", string header);
	string footer = (current / "</section>")[-1];

	if (argc > 3 && lower_case(argv[1]) == "show")
	{
		write(string_to_utf8(mpn_Hymn(sprintf("Hymn [%s %s] ...", argv[2], argv[3]))) + "\n");
		return 0;
	}

	if (argc > 1 && (argc&1))
	{
		array(string) parts = ({ });
		foreach (argv[1..]/2, [string book, string num])
			parts += ({mpn_Hymn(sprintf("Hymn [%s %s] ...", book, num))});
		Stdio.write_file("slides.html", string_to_utf8(header + (parts-({""}))*"\n" + footer));
		Process.create_process(({"git", "commit", "slides.html", "-mBuild slides for specific hymns"}))->wait();
		return 0;
	}

	string mpn; catch {mpn = Protocols.HTTP.get_url_data("http://gideon.rosuav.com:8000/mpn/sundaymusic.0");};
	if (!mpn) exit(1, "Unable to retrieve MPN - are you offline?\n");
	sscanf(utf8_to_string(mpn), "%d\0%s", int mpnindex, mpn); //Trim off the indexing headers

	//Assume that MPN consists of several paragraphs, and pick the first one with a hymn.
	foreach (mpn/"\n\n", string para)
	{
		para = String.trim_all_whites(para);
		if (!has_value(para, "\n") && has_prefix(para, "Sunday")) sermondate = para;
		else if (!service && (has_value(para, "\nHymn [") || has_prefix(para, "Hymn ["))) service = para;
		else if (service && has_value(para, "\n") && sermonnotes == "") sermonnotes = para;
	}
	if (!service) exit(1, "Unable to find Order of Service paragraph in MPN.\n(Are there colons before the hymn references again?)\n");

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
