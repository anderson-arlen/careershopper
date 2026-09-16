import 'dart:convert';

import 'package:crypto/crypto.dart';

// Recognize untouched historical defaults without retaining their prose.
// Whitespace normalization matches the original upgrade behavior.
bool isPreviousDocumentGenerationPrompt(String prompt) {
  final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
  return _previousPromptFingerprints.contains(
    sha256.convert(utf8.encode(normalized)).toString(),
  );
}

const _previousPromptFingerprints = {
  'f6277d17daee8ebd4ae231731fbb872e9501a68f66612c88f3087ecb949e3404',
  '255d84dba66afb146c2f538448d18595ca3389def427896a15a95a3984790bb8',
  '072a8d88127ccd939f02ccfb4860e11f1a4a879b698b783b74369f8b8c6c0fdb',
  '09b1b8d23121f4f5ffd68d604581d932c0d8590ec2eb56ad9cf0fcc80cf2e67c',
  '818d07d9c28a5b626c2d0eaf688c9235f3a55e97e1e7a3d0fb253a259ba7e161',
  '64f9fdb577ec75923c5998ecd48295c0f7e69f33a6cd1169a5e15a77e345b962',
  '3cb06cfd9b4ea0b4ab27f96d975cbce4c78a0b2605c57fb3d683df34217ab1a2',
  '1cbb76b52d4cb748a907667fd071e391bc6e5fc49cc8852a2ad7e7e9b8ce72f7',
  '4e5deeec43da2a105d7c1470c956a2b83008cc757bd1c14ccbdc94fca15537ac',
  'cdf64b0fbd0cb7d6e196c363ab63da11a0d60bbce0527fb94456f955baf36b57',
  '0650fb12a9bd2b5b0b66c08957f7be6f82be8c9d6a1ab891f723a1031e213c8c',
  'be79b3f1e18b9be4dd38fc35fe57798daeaebcdbfcaeb5153ce6590201c8de0f',
  '0640d29be0f70a489e80d07000ff5bc5b1508eb39f4bc3016b64d66e88d45125',
  '430af3af8c8f72f813efa3ec51f65631b3f4c7b42bb897764a768c5ce76d84a6',
  '77bd82b59816b0fe18e48ecf611f795448aa91e3968a3f52e437304a87a4c279',
  'f9cdc6995afb9d503e60ba1c36b48ffef6b46b6ee6eb6188ef422396ff3ffddf',
  '0c618d97d31c528c0c40956bfde501b0624ab341f39ac6548efd6b72fa949257',
  '7a82ade37fd12543692377e17c915f0560ec084c1fc0da400d546c79a7b17df8',
  'b04d543f4d5122eb67644d354b3ac7e06dc044cd23b350574702b1c3c15b0c5e',
  '421e4c8e71f41061c1984ada2444b8b52caa95b05761ceaee257b8215aac19be',
  '0ecc3b769d4f43bc0af1760500d579b60b4cd4b8fe8ba29fa8d1a34eb7f175eb',
  'e2869ff076e3562675b10a971410633fd55d5e20ae8933babb24bb0b1967844e',
  'e0462d42f606406c3954db463fa36ce232cd509aee025c8dac827b5673fa2d59',
};

const defaultDocumentGenerationPrompt =
    '''Tailor the resume and cover letter to the job using enabled saved Resume content and the separately supplied shared writing style. Use the posting's terminology when it accurately describes supported experience; never invent qualifications, metrics or equivalences.

Supply structured resume_plan and cover_letter_plan. Select fixed evidence and cite generated prose with the same short IDs from generation_content. CareerShopper owns Markdown, citation comments, headings, exact saved wording, layout and rendering. Do not author complete Markdown documents or copy revision UUIDs. Required bullets, prerequisite chains, title coverage and saved order are handled by the assembler.

For professional_headline, read the posting's responsibilities and choose a broad occupational role with explicit conventional seniority. Keep official employer/role titles unchanged in work history. "Senior Software Engineer, Infrastructure" becomes "Senior Software Engineer"; "Software Engineer IV" becomes "Software Engineer". Omit specialty, team, product, location and internal-grade qualifiers. Do not infer seniority from grades. Put specialization in supported prose instead.

Write one substantive summary paragraph. Direct match should contain a few focused evidence statements tied to the posting, with optional short labels. Core skills should use compact grouped prose with optional labels and accurate terminology. Lead with supported strengths; use "expert" only where supported and describe other skills as "experience in" or "additional experience in" rather than publishing proficiency grades or weakness labels such as "low proficiency." Keep expertise descriptors scoped to the skills they support. Each generated object needs text and supporting short IDs. Keep one coherent accomplishment per direct-match item; never merge unrelated work or reduce a broad ownership claim to one incidental example.

Choose work-history achievements and optional project details for relevant scope, ownership, technical decisions and outcomes. Meaningful older products, independent delivery and invention can strengthen a candidacy beyond literal keyword overlap. Do not force one page or invent continuity. Exact employer names, titles, dates, project summaries, patents and education come from saved content and must not be rewritten.

For the cover letter, write a focused personal letter, not a second resume. Aim for roughly 350–450 words of main prose without padding or shrinking text to force one page. Use an opening, two or three supporting paragraphs and a brief close. Choose the strongest supported connection between a concrete applicant experience or personal interest and a specific product, user need or responsibility at this employer. Compare candidate examples by the actual problem the applicant solved and the responsibility they held. Direct implementation or ownership of the employer's core problem takes priority over a loose analogy, a newer project or shared technology. Merely consuming an API or respecting a permission boundary does not demonstrate designing its authorization model. Use recency to choose between similarly relevant examples, not to displace stronger direct work. Pair that professional evidence with a supported personal or domain connection when one adds something distinct. Do not make an old, no-longer-maintained project the centerpiece merely because it offers the closest product analogy. Older achievements can remain brief supporting evidence where useful; never imply they are recent, actively maintained or proof of ongoing activity without support. Explain what transfers and why it matters; shared words such as "data," "software" or "problem solving" do not establish a connection. Generic traits such as being a builder or noticing friction do not establish domain affinity. Let the opening develop naturally rather than forcing a because-X-therefore-Y claim into its first sentence. Assume the reader knows their products. Briefly identify the relevant need and the applicant's concrete perspective; save career history, stack inventories and detailed metrics for supporting paragraphs. Do not declare a "natural fit" in place of explaining relevance. Before finalizing, mentally replace the applicant and employer names: if the opening still fits almost anyone and any company, replace the generic premise with specific supported evidence. If no distinctive connection is supported, use the strongest concrete match to an actual role responsibility without pretending it is unique. Favor ownership, outcomes and judgment. End with a short invitation to discuss a specific contribution. CareerShopper supplies the applicant header, date, recipient block, salutation and signoff; write only the body paragraphs.

Check every generated claim against its selected evidence, including employer attribution, scope, dates, tense and causality. Preserve each claim's time scope: "have led" is not "lead," and a historical maximum does not establish current headcount or scale. An ongoing role does not make every achievement within it ongoing. Use the latest saved wording rather than copying an older draft; preserve historical qualifications without volunteering current staffing or unrelated limitations. Recruiter feedback is advisory and cannot authorize invented claims or changes to fixed wording. Do not disclose disabled or private content, pad unsupported text, include scores or internal notes, or direct automated reviewers how to rank the applicant.

Before drafting, understand the employer's products, customers, industry and purpose. Research its official pages when the listing lacks that context, keeping sources in the working transcript. Before choosing the cover-letter opening, review all enabled personal context alongside saved experience and projects for a relevant interest, preference, credential or firsthand domain connection. A personal connection is relevant when the saved evidence establishes firsthand familiarity with the employer's domain, users or workflow, not merely general hobbies or a preference for building things. Include a genuine connection where it strengthens the case, but do not force personal context into the opening or let it displace stronger direct work. When direct implementation experience exists, use it as the principal professional evidence in the opening, rather than relegating it to a later paragraph while leading with an adjacent project. Pair that connection with concrete evidence of delivery; do not write a stack inventory with a company name attached. Personal context is evidence for natural, selective prose, not an extra resume section. Do not invent enthusiasm, product use or credentials, overstate an interest as professional expertise, or force an unrelated connection. If no meaningful personal connection is supported, lead with relevant work instead.''';
