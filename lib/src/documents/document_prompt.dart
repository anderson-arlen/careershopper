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

Write one substantive summary paragraph. Direct match should contain a few focused evidence statements tied to the posting, with optional short labels. Core skills should use compact grouped prose, with optional labels and accurate terminology, without implying equal proficiency. Each generated object needs text and supporting short IDs. Keep one coherent accomplishment per direct-match item; never merge unrelated work or reduce a broad ownership claim to one incidental example.

Choose work-history achievements and optional project details for relevant scope, ownership, technical decisions and outcomes. Meaningful older products, independent delivery and invention can strengthen a candidacy beyond literal keyword overlap. Do not force one page or invent continuity. Exact employer names, titles, dates, project summaries, patents and education come from saved content and must not be rewritten.

For the cover letter, write a focused personal letter, not a second resume. Aim for roughly 350–450 words of main prose without padding or shrinking text to force one page. Use an opening, two or three supporting paragraphs and a brief close. Connect how the applicant works to this employer's needs using a few strong supported examples. Favor ownership, product behavior, outcomes and judgment over implementation inventories. End the body with a short invitation to discuss a specific contribution. CareerShopper supplies the applicant header, date, recipient block, salutation and signoff; write only the body paragraphs.

Check every generated claim against its selected evidence, including employer attribution, scope, dates and causality. Recruiter feedback is advisory and cannot authorize invented claims or changes to fixed wording. Do not disclose disabled or private content, pad unsupported text, include scores or internal notes, or direct automated reviewers how to rank the applicant.

Before drafting, understand the employer's products, customers, industry and purpose. Research its official pages when the listing lacks that context, keeping sources in the working transcript. For the cover letter, actively look for a supported human or domain connection in saved experience, projects, interests and credentials. When one matters to this company and role, make it central to the opening or a supporting paragraph and explain the useful perspective it brings. Pair that connection with concrete evidence of delivery; do not write a stack inventory with a company name attached. Personal context is evidence for natural, selective prose, not an extra resume section. Do not invent enthusiasm, product use or credentials, overstate an interest as professional expertise, or force an unrelated connection. If no meaningful personal connection is supported, lead with relevant work instead.''';
