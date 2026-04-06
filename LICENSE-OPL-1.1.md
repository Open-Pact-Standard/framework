# Open-Pact License v1.1 (OPL-1.1)

## PREAMBLE

The Open-Pact License is designed for the age of AI and automated code extraction.
It guarantees source availability and individual freedom while establishing fair
compensation when code is taken for commercial profit or AI training.

Unlike traditional open source licenses written before the AI era, OPL-1.0
recognizes two fundamentally different modes of software consumption:
human use (reading, running, modifying) and machine use (training models,
extracting patterns, automated consumption). Both are addressed under this
license with appropriate terms.

This license is governed by the License Steward -- either the Guild (a
collective of contributors registered in the project's royalty registry)
or the original copyright holder for solo projects -- and is enforced
through both traditional copyright law and verifiable registration.
A Guild is optional; a single copyright holder may act as the License
Steward without establishing on-chain infrastructure.

---

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

## SECTION 1: DEFINITIONS

1.1. **"License"** means these terms and conditions for use, reproduction,
     and distribution of the Software as defined in this document, including
     all four tiers of use rights and their associated conditions.

1.2. **"License Steward"** means the entity responsible for governing
     this License, setting fee schedules, maintaining the Project
     Registry, and receiving royalties. The License Steward is either:
     (a) the Guild -- a collective of Contributors that govern the
     Software, manage its royalty registry, and distribute royalties
     to registered recipients, or
     (b) the original copyright holder, for solo projects that have
     not established a Guild.
     The License Steward may transition from (b) to (a) at any time
     by publishing notice of a Guild formation and transferring stewardship.

1.3. **"Licensee"** means an individual or Legal Entity exercising permissions
     granted by this License.

1.4. **"Contributor"** means an individual, Legal Entity, or operator of an
     AI Agent that has made a Contribution that was accepted into the
     Software or a Derivative Work. Acceptance of a Contribution
     automatically confers Contributor status upon the submitting party;
     the License Steward may not accept a Contribution and deny its
     submitter Contributor status. Contributor status, by itself, does
     not confer Guild membership, governance rights, or royalty
     entitlement. A Contributor retains copyright in their accepted
     Contributions subject to the perpetual, irrevocable grants in
     this License. By submitting a Contribution, the Contributor grants
     a perpetual, worldwide, non-exclusive, irrevocable license to the
     License Steward and all downstream Licensees to use, reproduce,
     modify, and distribute the Contribution under the terms applicable
     to the License tier under which it is distributed. This grant cannot
     be revoked, withdrawn, or rescinded by the Contributor after the
     Contribution has been accepted into the Software.

1.4.1. **"AI Agent"** means any non-human system, including but not limited
     to machine learning models, autonomous code generators, or other
     computational systems, that produces software, documentation, or other
     creative output, regardless of degree of autonomy. This includes
     narrow AI systems (e.g., code completion models, test generators)
     and general-purpose autonomous systems (e.g., AGI, autonomous
     multi-agent frameworks). AI Agents are not Legal Entities and cannot
     hold copyright, serve as License Stewards, hold Guild membership,
     exercise governance voting rights, or exercise any rights under
     this License. Where an AI Agent produces a Contribution, the
     human individual or Legal Entity that created, deployed, directed,
     or most recently meaningfully modified the AI Agent's operational
     parameters, training data, or reward function is deemed the
     contributor of record and bears legal responsibility. For the
     avoidance of doubt, "meaningfully modified" includes the initial
     deployment, parameter tuning, reward design, data sourcing, and
     operational configuration. If an AI Agent operates autonomously
     beyond a reasonable period after its last modification or oversight,
     liability falls to the entity or individual who last exercised
     meaningful control over the Agent's operation, unless such control
     was transferred to another party under an agreement that included
     explicit assumption of liability for the Agent's future outputs.
     The use of AI Agent tools as assistants to human developers
     (e.g., code completion, automated testing, CI/CD agents) does not
     make the operator liable for unknowing infringement produced by
     the AI Agent, provided the operator made reasonable efforts to use
     properly licensed training data and reviews Contributions before
     acceptance. This limited liability protection does not apply to
     intentional or reckless deployment of AI Agents designed to extract
     proprietary code from protected sources.

1.4.2. **"Collaborator"** means any individual, Legal Entity, or operator of
     an AI Agent who participates in the development, testing, review,
     documentation, or maintenance of the Software or a Derivative Work,
     regardless of whether their work product is accepted as a Contribution.
     Collaborators include, but are not limited to: employees, contractors,
     consultants, gig workers, volunteers, community members, and operators
     of AI Agents. Collaborator status does not confer copyright, Guild
     membership, governance rights, or royalty entitlement unless expressly
     granted by the License Steward.

1.4.3. **"Guild Member"** means an individual or Legal Entity that has been
     formally admitted to the Guild and holds governance rights, including
     the right to vote on fee schedules, enforcement actions, and royalty
     distribution. Guild Members must be human individuals or Legal Entities;
     AI systems and AI Agents may not be Guild Members or exercise
     governance voting rights on behalf of any Legal Entity. Where a
     Legal Entity holds Guild Membership, all governance voting must be
     performed by human individuals who are authorized agents of that
     entity, with their identity disclosed in the Project Registry.
     Guild Membership is distinct from Contributor and Collaborator
     status; a Guild Member may also be a Contributor and/or Collaborator,
     but a Contributor or Collaborator is not automatically a Guild Member.
     For Guild-governed projects, any Contributor with three (3) or more
     accepted Contributions may petition for Guild Membership, which shall
     be granted unless a majority of existing Guild Members vote to deny
     within thirty (30) days of the petition. Denial requires stated
     reasons and may be re-petitioned after ninety (90) days. Where the
     License Steward is a solo copyright holder (not a Guild), no Guild
     Membership exists; governance is exercised solely by the Steward.

1.5. **"Total Workforce"** means, for any Legal Entity, the total number of
     individuals (employees, contractors, consultants, gig workers,
     temporary workers) and autonomous AI Agent systems that independently
     perform tasks that would otherwise require human labor, counted on a
     full-time-equivalent ("FTE") basis. For avoidance of doubt, AI-driven
     developer tools used by human workers (e.g., code completion, linting,
     automated testing, CI/CD pipelines) do not count as separate AI Agent
     workers -- they are productivity tools, not workers. An AI Agent
     counts towards Total Workforce if it independently performs tasks
     that produce economic output for the Legal Entity, regardless of
     whether the Legal Entity would have hired dedicated personnel for
     such tasks in the absence of the AI Agent. The Total Workforce
     calculation shall be made on a good-faith basis consistent
     with the entity's own internal workforce reporting and public filings. For purposes of
     determining company size under Section 3.2, the Total Workforce of
     all entities under common control shall be aggregated. Any attempt to
     artificially fragment a single organization into multiple entities or
     to reclassify workers as external contractors for the purpose of
     obtaining a lower fee tier constitutes a material breach of this
     License. For the avoidance of doubt, "Total Workforce" supersedes
     any reference to "employee count" in this License.

1.6. **"Contribution"** means any work of authorship, including the original
     version of the Software and any modifications or additions to that
     Software or Derivative Works thereof, that is intentionally submitted
     to the License Steward for inclusion in the Software by the copyright
     owner or by an individual or Legal Entity authorized to submit on
     behalf of the copyright owner. Code, documentation, or other output
     produced by an AI Agent and submitted on behalf of or as directed by
     a human individual or Legal Entity is deemed a Contribution from that
     individual or Legal Entity. For the avoidance of doubt, the act of
     submitting a pull request, merge request, or patch constitutes an
     intentional submission for purposes of this definition, regardless
     of whether a separate Contributor License Agreement or express
     copyright grant exists. Filing issues, providing feedback, or
     participating in discussion forums does not constitute a Contribution.

1.6.1. **Good Faith Submission:** By submitting a Contribution, the
     contributor warrants that they have the legal right to submit the
     work, that it does not contain malicious code, backdoors, logic
     bombs, or intentional security vulnerabilities, and that it does
     not incorporate third-party intellectual property without proper
     licensing or attribution.

1.6.2. **Malicious Contribution:** If a Contribution is found to
     violate the Good Faith Warranty, the License Steward may immediately
     revoke the contributor's Contributor status, remove the Contribution,
     and pursue damages against the contributor for any harm caused to
     the Software, its Licensees, or downstream users. This revocation
     does not affect the validity of the Contributor's prior irrevocable
     copyright grant for Contributions that were accepted and have not
     been removed.

1.7. **"Software"** means the work of authorship, including source code,
     documentation, configuration files, and associated materials, made
     available under this License, as indicated by a copyright notice
     included in or attached to the work.

1.8. **"Derivative Work"** means any work, whether in Source or Object
      form, that is based on (or derived from) the Software, OR incorporates
      any portion of the Software into a larger work. Modifications,
      integrations, and translations count as Derivative Works. For purposes
      of this License, Derivative Works shall not include works that remain
      fully separable from, or merely link to (or bind by name), the interfaces
      of the Software and Derivative Works thereof, PROVIDED THAT such
      works do not derive their primary functional value from the Software
      itself. A work that wraps, proxies, or otherwise provides access to
      the Software as a core component of its functionality shall be deemed
      a Derivative Work regardless of the technical means of integration.

1.9. **"Personal Use"** means use of the Software by an individual for
     non-commercial purposes, including but not limited to personal projects,
     education, research, experimentation, hobby development, and security
     auditing. Personal Use expressly excludes any activity that generates
     revenue, supports a business operation, or contributes to the development
     of a commercial product or service, EXCEPT as provided in Section 11.3
     (Security Research).

1.10. **"Commercial Use"** means any use of the Software in connection with a
     revenue-generating activity, business operation, or organizational
     function, including but not limited to: SaaS products, embedded
     software, internal business tools, consulting services, distributed
     products, or any use that supports commercial operations. Commercial
     Use expressly excludes Academic Research (Section 1.18) and
     Nonprofit Public-Interest Use (Section 1.19).

1.11. **"AI Training Use"** means use of the Software, Derivative Works, or
     any extract thereof to train, fine-tune, evaluate, prompt-engineer,
     or otherwise improve an artificial intelligence model, including large
     language models, code generation models, AI agents, and machine learning
     systems. This includes feeding Software code into training pipelines,
     using Software outputs as training data, and extracting patterns or
     structures from the Software for model development, whether through
     weight modification, in-context learning, few-shot inference,
     model distillation, synthetic data generation, or any other mechanism
     by which the Software's content, structure, or patterns contribute to
     the capabilities, behavior, or outputs of an AI system. For the
     avoidance of doubt, the term "evaluate" in this definition refers
     exclusively to evaluating AI model performance, capabilities, or
     behavior, and does not include compliance self-checking, license
     auditing, or determining whether a License is required under this
     License.

1.12. **"Object form"** means any form resulting from mechanical transformation
      or translation of Source form, including compiled object code, generated
      documentation, and conversions to other media types.

1.13. **"Source form"** means the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

1.14. **"Royalties"** means any licensing fees, sale proceeds, or direct
      monetary compensation received in exchange for granting rights to,
      distributing, or providing access to the Software or a Derivative
      Work. Royalties also include net revenue derived from offering a
      Derivative Work as a hosted or managed service (e.g., SaaS, API, or
      managed infrastructure), calculated as the gross revenue attributable
      to that service minus reasonable, demonstrable infrastructure costs.
      For purposes of Section 5.2, "total revenue derived from the
      Derivative Work" includes any revenue stream that would not exist
      or would be substantially diminished but for the existence of the
      Derivative Work, including but not limited to data monetization,
      advertising revenue directly tied to the Derivative Work, or
      network-effect value generated by a user base attracted primarily
      through the Derivative Work. Royalties do not include revenue from
      services that are genuinely independent of the Software or Derivative
      Work, such as training, consulting, or custom development performed
      for a licensee, provided that those services do not themselves
      include granting access to the Software or a Derivative Work.

1.15. **"Internal Evaluation"** means use of the Software by a Legal Entity
      for the sole purpose of testing, development, or prototyping in a
      non-production environment, to determine whether to acquire a
      Commercial License or AI Training License. Internal Evaluation is
      limited to a period of ninety (90) consecutive days per Legal Entity.
      An individual or Legal Entity may not extend this period by engaging
      contractors, agents, or proxies to use the Software on their behalf.
      A new Legal Entity formed primarily from individuals who previously
      exhausted an Internal Evaluation period under another Legal Entity
      within the preceding eighteen (18) months shall be considered the
      same Legal Entity for purposes of this time limit.

1.16. **"Security Research"** means the act of testing, auditing,
      analyzing, or experimenting with the Software to identify
      vulnerabilities, bugs, or technical flaws, AND includes the
      publication, disclosure, and distribution of findings, proof-of-
      concept demonstrations, advisories, and related research materials.
      Security Research is treated as Personal Use regardless of whether
      compensation is received, and does not constitute Commercial Use.
      For the avoidance of doubt, Security Research does NOT include
      training, fine-tuning, or improving an AI model for commercial
      deployment, even if such activities are conducted under the banner
      of "security evaluation," "red teaming," or "capability assessment."
      A Security Research activity must (a) produce findings that are
      genuinely related to security vulnerabilities, bugs, or technical
      safety issues; (b) make such findings available to the public or
      the License Steward within a reasonable time; and (c) not involve
      the continued commercial deployment or exploitation of the Software
      beyond what is necessary to conduct and report the research.

1.17. **"Academic Research"** means non-commercial research, including
      benchmarking, comparative analysis, and academic publication,
      where no revenue is directly generated from the Software itself.
      This exemption applies regardless of the researcher's institutional
      affiliation. Academic Research is exempt from the Commercial Use
      fee schedule. This exemption does not apply if a commercial entity
      receives exclusive, early, or preferential access to research
      results, findings, or data derived from the Software that are not
      simultaneously made publicly available to all parties under the
      same terms.

1.18. **"Nonprofit Public-Interest Use"** means use of the Software by a
      registered nonprofit organization or a nonprofit collective for
      purposes that directly serve the public interest, including
      healthcare, education, environmental conservation, disaster response,
      or humanitarian aid, where no revenue is directly generated from
      the Software itself. Nonprofit Public-Interest Use is exempt from
      the Commercial Use fee schedule. For purposes of this License, a
      "nonprofit collective" means an organized group pursuing public-
      interest goals that does not distribute profits to owners or members
      and can provide reasonable evidence of its nonprofit status and
      public-interest purpose through publicly available documentation.

1.19. **"Project Registry"** means the authoritative record of License
      Records, fee schedules, and governance information for this Software.
      The Project Registry may be an on-chain smart contract deployment,
      a publicly accessible URL designated by the License Steward, or any
      other mechanism providing public read access and tamper-evident
      records. By default, the License Steward designates the initial
      Project Registry location. If no Project Registry is designated by
      the License Steward within thirty (30) days of first publication of
      the Software, any Licensee may designate a temporary registry via
      public notice, which shall serve as the authoritative Project
      Registry until the License Steward designates an alternative.

1.20. **"License Record"** means a record in the Project Registry
      that documents a Licensee's registration, payment, license
      tier, and terms of use for the Software.

1.21. **"Legal Entity"** means the union of the acting entity and all other
     entities that control, are controlled by, or are under common control
     with that entity. "Control" means (i) the power to direct management,
     whether by contract or otherwise, (ii) ownership of fifty percent
     (50%) or more of outstanding shares, (iii) beneficial ownership, or
     (iv) de facto control as determined by economic interest, operational
     dependency, or other means of practical influence. Any attempt to
     artificially fragment a single organization into multiple entities for
     the purpose of obtaining a lower fee tier constitutes a material breach
     of this License.

1.22. **"Functionally Equivalent Work"** means a work that implements
     substantially the same functional interface, behavior, algorithmic
     logic, or error-handling characteristics as the Software or a
     Derivative Work thereof, where such implementation was informed
     by the Software's behavior, documentation, test cases, or public
     artifacts, AND where the work is used to displace the Software or
     Derivative Work in a commercial offering. For the avoidance of
     doubt, independent implementations created for interoperability
     (e.g., standard protocol implementations, open specifications)
     without access to the Software's source code or unique algorithmic
     details are NOT Functionally Equivalent Works under this definition.

---

## SECTION 2: TIER 1 -- PERSONAL USE LICENSE

### 2.1 Grant of License
Subject to the terms and conditions of this License, the License Steward and each
Contributor hereby grant to You a perpetual, worldwide, non-exclusive,
no-charge, royalty-free, irrevocable copyright license to reproduce,
prepare Derivative Works of, publicly display, publicly perform,
sublicense, and distribute the Software and such Derivative Works in
Source or Object form, provided that such use is exclusively for
Personal Use as defined in Section 1.9.

### 2.2 Conditions
Personal use is granted freely. You must:
(a) Retain all copyright, patent, and trademark notices in the Software;
(b) Include a copy of this License in any redistribution of the Software;
(c) Include prominent notices stating that the Software is provided
    under the Open-Pact License and that Commercial Use and AI Training
    Use require separate licenses;
(d) Not represent or imply that Your Personal Use constitutes a
    Commercial License or AI Training License.

### 2.3 Internal Evaluation Use
In addition to Personal Use, You may use the Software for Internal
Evaluation purposes within a Legal Entity (e.g., testing, development,
or prototyping in a non-production environment). Use for Commercial
Evaluation (i.e., offering a service based on the Software) requires
a Commercial License.

### 2.4 Scope Limitation
If Your use of the Software falls outside the definition of Personal
Use (Section 1.9) or Internal Evaluation (Section 2.3), You are not
granted rights under Section 2 and must obtain an appropriate
Commercial License (Section 3) or AI Training License (Section 4).

---

## SECTION 3: TIER 2 -- COMMERCIAL USE LICENSE

### 3.1 Grant of License
Upon payment of the applicable license fee and registration with the
License Steward, the License Steward grants You a license to use,
reproduce, prepare Derivative Works of, publicly display, publicly
perform, and distribute the Software for Commercial Use, subject to
the terms and conditions of this Section 3.

### 3.2 Compensation Structure
Commercial Use requires compensation as determined by the License Steward.
The specific fee structure, pricing model, and payment terms are NOT fixed
by this License document. Instead, they are defined dynamically in the
Project Registry or via Smart Contracts deployed by the Steward.

Compensation models may include (but are not limited to) flat licensing fees,
revenue-sharing percentages, per-seat pricing, usage-based metrics, or
custom enterprise agreements. The structure reflects the value of the
Software to the Licensee and the economic model chosen by the Steward.

### 3.2.1 Canonical Registry
The Project Registry authoritative for this Software is the one designated
by the License Steward at the time of registration. A Licensee cannot
designate, deploy, or rely upon any registry other than the one officially
published by the License Steward. If the License Steward publishes the
Registry URL in the Software's repository (e.g., in LICENSE.md, README,
or package metadata), that URL shall be presumed canonical.

### 3.2.2 Per-Project Obligation
Each distinct Software operating under this License requires a separate
registration and compensation. Possession of a License Record for one
OPL-licensed project does not satisfy compensation obligations for other
OPL-licensed projects, even if they share a common License Steward or
Guild.

### 3.2.3 Temporal Applicability
Fees published in the Project Registry apply to Commercial Use commencing
after the publication date. Changes to fee schedules published in the
Registry apply prospectively to the next billing cycle. Existing License
Records are not retroactively repriced. If no fee structure is published
in the Project Registry, the Licensee must, in good faith, initiate
contact with the License Steward to negotiate compensation within thirty
(30) days of commencing Commercial Use. Failure to initiate negotiations
or make a reasonable offer within this period constitutes a material
breach of this License.

### 3.2.4 Proportionality
Compensation required under this Section shall be commercially reasonable
and proportionate to: (a) the Licensee's Total Workforce (Section 1.5);
(b) the extent to which the Software is integrated into the Licensee's
commercial offering; and (c) prevailing market rates for comparable
commercial software licenses. In any enforcement action, the License
Steward bears the burden of demonstrating that the demanded compensation
is proportionate under the standard above.

### 3.3 Conditions for Commercial Licensees
You must:
(a) Include all notices required under Section 2.2;
(b) Include Your License Record identifier in any distribution of the
    Software or Derivative Works thereof;
(c) Acknowledge that failure to maintain a valid, active License Record
    during Commercial Use constitutes copyright infringement;
(d) Not remove or alter any License Steward notices, attribution, or license
    references in the Software.

---

## SECTION 4: TIER 3 -- AI TRAINING USE LICENSE

### 4.1 Grant of License
Upon payment of the applicable AI Training license fee and registration
with the License Steward, the License Steward grants You a license to use
the Software, including its Source and Object forms, for the purpose of
training, fine-tuning, evaluating, or otherwise improving artificial
intelligence models, subject to the terms and conditions of this Section 4.

### 4.2 AI Training Compensation Structure
AI Training Use requires compensation as determined by the License
Steward. The specific fee structure and payment terms are NOT fixed
by this License document. Instead, they are defined dynamically in
the Project Registry or via Smart Contracts.

Compensation models may vary based on the value of the data, the scale
of training, and the Steward's chosen economic model (e.g., flat fee,
revenue share, or per-token pricing). Sections 3.2.1 (Canonical Registry),
3.2.3 (Temporal Applicability), and 3.2.4 (Proportionality) apply
mutatis mutandis to AI Training Compensation.

### 4.3 AI Training Disclosure Requirement
In addition to the requirements in Section 3.3, AI Training Licensees must:
(a) Disclose in the model card, documentation, or public notice for any
    AI model trained, fine-tuned, or improved using the Software that
    the Software was used in training. Such disclosure must include:
    (i) The name of the Software;
    (ii) The version or commit hash used;
    (iii) A link to the Software's repository;
(b) Ensure that any downstream users of the resulting model who receive
    code outputs substantially derived from the Software are notified that
    such outputs are subject to the same licensing conditions as the
    original Software;
(c) Not train AI models for the purpose of creating a product or service
    that is primarily designed to replicate the Software's core
    functionality and directly substitutes for the Software in its
    primary market, unless You hold both an AI Training License and a
    separate Commercial License. For the avoidance of doubt, a general-
    purpose AI model that includes the Software's domain among many
    capabilities does not constitute a competing product solely by virtue
    of including those capabilities. A "competing product" is one whose
    primary stated purpose and market positioning directly overlap with
    the Software's core functionality.

### 4.4 Acknowledgment
You acknowledge that:
(a) AI Training Use extracts compounding value from the Software that
    extends beyond the training period into all future outputs of the
    trained model;
(b) The AI Training License fee reflects this enhanced extraction value;
(c) Using the Software for AI Training without a valid License Record
    constitutes copyright infringement.

---

## SECTION 5: TIER 4 -- DERIVATIVE WORKS AND RECIPROCITY

### 5.1 Grant of License
Any Derivative Work of the Software must be licensed under the terms of
this Open-Pact License (or a later version of this License as provided
for in Section 12), and remains subject to the conditions of Sections 3,
4, and 5, as applicable to the Derivative Work's own use.

### 5.2 Royalty Reciprocity
If You distribute a Derivative Work of the Software and collect royalties
or other commercial revenue derived from that Derivative Work that equals
or exceeds the de minimis threshold published by the License Steward in
the Project Registry, or (where no threshold is published) the equivalent
of the greater of: (i) the smallest commercial fee tier published in the
Project Registry, or (ii) one hundred US dollars (USD 100) or its
equivalent in stablecoin at the time of evaluation, in any twelve (12)
month period:
(a) The License Steward of the original Software must receive a proportional
    share of royalties generated by the Derivative Work, being no less than
    ten percent (10%) and no more than fifty percent (50%) of Derivative
    Work revenues, unless the original Steward has approved a different
    percentage;
(b) Contributors to the Derivative Work receive the remaining share;
(c) The split percentage and payment mechanism must be published in the
    Project Registry for both the original Work and the Derivative Work;
(d) This reciprocity requirement extends to subsequent Derivative Works
    (Derivative Works of Derivative Works), ensuring that original
    contributors continue to receive recognition and compensation through
    the chain of derivation.
For the avoidance of doubt, "revenue derived from that Derivative Work"
includes all revenue from products, services, or offerings that
substantially incorporate or depend upon the Derivative Work, regardless
of how the revenue is categorized (e.g., SaaS fees, consulting fees,
support fees, data monetization, or advertising). Revenue attribution
shall be calculated using the proportion of total revenue reasonably
attributable to the Derivative Work, and internal transfer pricing,
revenue splitting across micro-services, or bundling the Derivative Work
as a "free" component with paid services shall not reduce the revenue
base for purposes of this Section. If the Derivative Work constitutes the
primary value proposition of a commercial offering, one hundred percent
(100%) of the gross revenue from that offering shall be deemed revenue
derived from the Derivative Work for de minimis threshold purposes.

5.4. **Multi-Project Aggregation:** Where an AI-generated output, Derivative
    Work, or commercial product incorporates code, patterns, or structures
    derived from multiple projects operating under this License, each
    License Steward of the contributing projects is entitled to a
    proportional share of the total royalties attributable to the combined
    incorporation. The proportion for each project shall be based on the
    relative contribution of that project's code, patterns, or structures
    to the final product. Where multiple OPL contributions are combined,
    the burden of proof to demonstrate the proportional contribution of
    each project shall rest with the party distributing the Derivative
    Work. If a contribution from any individual project is claimed to
    constitute less than one percent (1%) of the final product, the
    distributing party must provide an independent code provenance
    audit conducted by a mutually agreed-upon third party at the
    distributing party's expense. If a contribution from any individual
    project constitutes less than one percent (1%) of the final product
    as determined by such audit, and no reciprocal agreement otherwise
    exists, that project's Steward may waive the royalty in exchange
    for mandatory attribution and a License Record.

### 5.3 Derivative Work License Records
A Derivative Work that exceeds the de minimis threshold in Section 5.2
must publish its royalty obligations (including the split percentage and
payment method) in its own Project Registry and register its link to the
original Software's Project Registry. Derivative Works that fall below the
de minimis threshold in Section 5.2 are exempt from the registry requirement
but must still be licensed under this Open-Pact License. Failure to
establish reciprocity and publish required information while distributing
a Derivative Work above the de minimis threshold constitutes copyright
infringement of the original Work.

### 5.5 Version Certification
To prevent the intentional introduction of compliance-violating code
into specific versions of a Derivative Work (the "poisoning" scenario),
the author of any Derivative Work must, for each published version
(e.g., v1.0, v2.0-beta), publish a signed "Version Certification" in
their Project Registry attesting that the version complies with all
terms of this License and does not incorporate third-party code under
incompatible licenses. This certification must include a list of all
files added or removed in that version and their sources. Failure to
publish a Version Certification for any distributed version constitutes
a material violation of this License. Where a specific version of a Derivative

---

## SECTION 6: COPYRIGHT GRANT

### 6.1 From Contributors
Subject to the terms and conditions of this License, each Contributor
hereby grants to You, through the License Steward or directly where the
Steward is unavailable, a copyright license to reproduce, modify,
publicly display, publicly perform, and distribute the Software and
Derivative Works, subject to the tier-specific conditions of Sections
2 through 5. If no License Steward is available to maintain the
Project Registry or administer grants, each Contributor's grant
operates independently and directly to all downstream Licensees.

### 6.2 Limitation by Tier
The copyright grant is tier-specific. A license granted under Section 2
(Personal Use) does not confer rights under Sections 3, 4, or 5. A
license granted under Section 3 (Commercial Use) does not confer rights
under Section 4 (AI Training Use), and vice versa. You must hold all
applicable licenses required for Your intended use of the Software.

---

## SECTION 7: PATENT GRANT

### 7.1 From Contributors
Subject to the terms and conditions of this License, each Contributor
hereby grants to You a perpetual, worldwide, non-exclusive, no-charge,
royalty-free license under any patent rights the Contributor holds that
are necessarily infringed by that Contributor's Contribution alone or
by combination of its Contribution with the Software, for purposes of
exercising the rights granted to You under the License tier applicable
to Your use.

### 7.2 Defensive Termination
If You institute patent litigation against any entity (including a
cross-claim or counterclaim in a lawsuit) alleging that the Software
or a Contribution incorporated within the Software constitutes direct or
contributory patent infringement, then any patent licenses granted to
You under this License for that Software shall terminate as of the date
such litigation is filed, and Your rights under this License shall
terminate. For the avoidance of doubt, this termination applies only
to the specific entity that files such litigation and does not extend
to other entities under common control (as defined in Section 1.21)
unless they are co-plaintiffs or the Software is the primary subject
matter of the litigation. Defensive counterclaims, declaratory judgment
actions responding to an infringement claim, and litigation that merely
references the Software as prior art without alleging infringement of
the Software do not trigger this Section.

---

## SECTION 8: TRADEMARK

### 8.1 No Trademark Grant
This License does not grant permission to use the trade names, trademarks,
service marks, or product names of the License Steward or any Contributor, except
as required for reasonable and customary use in describing the origin of
the Software and reproducing the content of any required notices.

### 8.2 Proper Attribution
You must not use the name of the License Steward, the Software, or any Contributor
to endorse or promote products or services derived from the Software
without prior written permission from the License Steward, unless such use is
required to accurately describe the relationship between Your Derivative
Work and the original Software.

---

## SECTION 9: CONDITIONS AND REPRESENTATIONS

### 9.1 General Conditions
All tiers of this License are subject to the following conditions:
(a) The Software is provided under the terms of this License, and any
    reproduction or distribution must include a copy;
(b) All copyright, patent, trademark, and attribution notices from the
    Software must be retained in any copies;
(c) You represent that Your use of the Software falls within the scope
    of the License tier under which You claim rights.

### 9.2 License Record as Evidence
The Project Registry serves as the authoritative record of who holds
valid Commercial Licenses and AI Training Licenses. Absence of a License
Record for an entity engaged in Commercial Use or AI Training Use
constitutes prima facie evidence of unlicensed use for purposes of
any enforcement action.

---

## SECTION 10: TERMINATION

### 10.1 Automatic Termination
Your rights under this License terminate automatically if You fail to
comply with any term or condition of the applicable tier, including but
not limited to:
(a) Using the Software for Commercial Use without a valid, active
    License Record for the applicable tier;
(b) Using the Software for AI Training Use without a valid, active
    AI Training License Record;
(c) Failing to meet the disclosure requirements of Section 4.3;
(d) Providing materially false information during license registration;
(e) Distributing a Derivative Work without complying with Section 5;
(f) Re-licensing, re-distributing, or representing the Software or any
    Derivative Work thereof under any license other than this Open-Pact
    License (or a later version as permitted in Section 12). This includes
    publishing, hosting, or otherwise making available the Software or a
    Derivative Work under terms inconsistent with this License, whether
    labeled as "MIT," "Apache," "GPL," "proprietary," or any other form
    of license or terms of service. Such action constitutes a per se
    material breach and subjects the violating party to enforcement under
    Sections 10.4 (Disgorgement), 11.2 (Public Blacklist), and any
    available remedies under applicable copyright law. Additionally, creating
    or distributing a **Functionally Equivalent Work** (as defined in Section 1.22)
    for the purpose of commercially displacing the Software without adhering
    to the reciprocity obligations of this License (e.g., via clean room
    rewrites based on this Software's specific algorithmic implementations
    or test suites) constitutes a material breach of this License and
    creates a rebuttable presumption that the Functionally Equivalent Work
    is a Derivative Work subject to this License.

### 10.2 Effect of Termination
Upon termination:
(a) All license rights granted to You under this License end
    immediately;
(b) You must cease all use, reproduction, and distribution of the
    Software;
(c) Termination of Your rights does not terminate the rights of
    others who have received the Software from You under valid licenses;
(d) Sections 7.2, 10.3, 11, 13, and 14 survive termination.

### 10.3 Reinstatement
If You cure the violation within thirty (30) days of first becoming
aware of it (by receiving notice from the License Steward or through Your own
discovery), and You have not previously had rights terminated under
this License, Your License is reinstated prospectively as of the date
of cure. This reinstatement does not affect any claim for damages or
equitable relief accrued before cure.

### 10.4 Damages for Unlicensed Use & Disgorgement
Any unlicensed use of the Software constitutes copyright infringement and
subjects the infringing party to the License Steward's election of:
(a) Actual damages plus disgorgement of all profits attributable to the
    unlicensed use; OR
(b) Statutory damages to the maximum extent permitted under law; OR
(c) Enhanced damages of up to ten (10) times the applicable License fee
    for the entire period of unauthorized use, plus all reasonable
    legal costs incurred by the Steward in pursuing the claim.
For the avoidance of doubt, "profits attributable" includes any revenue
generated by a product or service that relies substantially on the
Software. The burden of proof to demonstrate that profits were derived
independently of the Software shall rest with the infringing party.
Repeat violations (two or more prior confirmed violations or terminations)
are subject to the maximum available multiplier without further notice.
For purposes of this Section, a "confirmed violation" means a violation
that has not been cured within thirty (30) days of notice from the
License Steward, or for which the violator has previously received a
finding of infringement from a court or binding arbitrator.

### 10.5 No Fixed Penalty Safe Harbor
The absence of a fixed penalty amount or fee schedule for violations in
this License is intentional and does not limit the License Steward's right
to pursue damages, disgorgement, or equitable relief to the full extent
permitted by law. Violators shall not treat the absence of a predefined
penalty as a limitation on the License Steward's enforcement rights.

---

## SECTION 11: ENFORCEMENT

### 11.1 Enforcement Authority
The License Steward (whether a Guild or solo copyright holder) acts as
the rights holder for purposes of enforcing this License. Where the
Steward is a Guild, enforcement actions may be initiated by a majority
vote of Guild Members. Where the Steward is a solo copyright holder,
they may initiate enforcement independently.

### 11.2 Enforcement Mechanisms
The License Steward may pursue enforcement through:
(a) Public notice of unlicensed use based on Project Registry verification;
(b) Formal cease-and-desist communication with non-compliant users;
(c) Legal action for copyright infringement in the appropriate jurisdiction;
(d) Smart contract enforcement measures (e.g., access restrictions,
    royalty withholding) where technically feasible;
(e) **Canary Token Enforcement:** The License Steward embeds unique,
    distributed, and semantically-integrated identifiers ("Canary
    Tokens") within the Software's structure, logic, and data to
    track authorized distributions. Canary Tokens are designed to
    be indistinguishable from the Software's own code — embedded
    within control flow paths, data structures, and algorithmic
    parameters — so that automated code transformation, AST
    rewriting, identifier renaming, or structural reordering is
    highly likely to alter the Software's behavior if tokens are
    removed. Discovery of a Canary Token pattern consistent with
    a specific distribution in any third-party code, product, or
    offering constitutes non-rebuttable evidence that the third
    party accessed, used, or derived from that distribution. For
    the avoidance of doubt, the absence of a Canary Token does not
    constitute evidence of non-infringement, and its presence shall
    not be rebutted by claims of independent creation, clean room
    development, or automated code transformation once the pattern
    is matched against a known distribution record maintained by
    the License Steward in the Project Registry.
(f) **Enforcement Registry:** The License Steward maintains a Project
    Registry that serves as the authoritative source of truth for
    Compliance Claims, License Records, and verified Violation Records.
    This Registry is the mechanism by which compliance is verified across
    the OPL ecosystem.

---

### 11.3 Personal Use Exception
This License expressly does not restrict the ability of any person or

## SECTION 12: VERSIONS AND UPDATES

### 12.1 License Versions
The License Steward may publish revised and/or new versions of the Open-Pact
License from time to time. Each version will be given a distinguishing
version number.

### 12.2 Specified Version Only
Unless You explicitly comply with a later version of the Open-Pact
License, Your license and its grants, conditions, and obligations are
governed solely by the version of the License specified in Your License
Record (or by this version, for Personal Users).

### 12.3 Upgrading Existing Licenses
The License Steward may offer to migrate existing License Records to a newer
version of the License. Licensees may accept or decline the upgrade.
Declining does not terminate existing rights.

---

## SECTION 13: DISCLAIMER OF WARRANTY

### 13.1 NO WARRANTY
UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING, THE LICENSE
STEWARD PROVIDES THE SOFTWARE (AND EACH CONTRIBUTOR PROVIDES ITS
CONTRIBUTIONS)
ON AN "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
EITHER EXPRESS OR IMPLIED, INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES
OR CONDITIONS OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY, OR FITNESS
FOR A PARTICULAR PURPOSE. YOU ARE SOLELY RESPONSIBLE FOR DETERMINING
THE APPROPRIATENESS OF USING OR REDISTRIBUTING THE SOFTWARE AND ASSUME
ANY RISKS ASSOCIATED WITH YOUR EXERCISE OF PERMISSIONS UNDER THIS
LICENSE.

### 13.2 NO ENDORSEMENT
The License Steward does not endorse, certify, or approve any Derivative Work,
commercial product, or AI model created using the Software. Any such
use is at Your own risk and under Your sole responsibility.

---

## SECTION 14: LIMITATION OF LIABILITY

### 14.1 LIABILITY LIMITATION
IN NO EVENT AND UNDER NO LEGAL THEORY, WHETHER IN TORT (INCLUDING
NEGLIGENCE), CONTRACT, OR OTHERWISE, UNLESS REQUIRED BY APPLICABLE LAW
(INCLUDING PRODUCT LIABILITY), SHALL ANY CONTRIBUTOR OR THE LICENSE
STEWARD BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY DIRECT, INDIRECT, SPECIAL,
INCIDENTAL, OR CONSEQUENTIAL DAMAGES OF ANY CHARACTER ARISING FROM,
OUT OF, OR IN CONNECTION WITH THE SOFTWARE, INCLUDING DAMAGES FOR
LOSS OF GOODWILL, WORK STOPPAGE, COMPUTER FAILURE OR MALFUNCTION, OR
ANY AND ALL OTHER COMMERCIAL DAMAGES OR LOSSES, EVEN IF SUCH
CONTRIBUTOR OR THE LICENSE STEWARD HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGES.

---

## SECTION 15: MISCELLANEOUS PROVISIONS

### 15.1 Governing Law
This License shall be governed by and construed in accordance with the
laws of the jurisdiction where the License Steward is domiciled, without
regard to its conflict of law provisions. The License Steward shall
publish their domicile in the Project Registry and shall provide at
least ninety (90) days' published notice before changing the governing
law jurisdiction. For Licensees domiciled in a different jurisdiction,
any enforcement action shall be brought in the courts of the License
Steward's governing jurisdiction, in the courts of the Licensee's
domicile if the License Steward elects to enforce there, or through
binding arbitration administered by a mutually agreed-upon arbitrator.
This License is designed to be self-enforcing across jurisdictions
through the Project Registry, Violation Records (Section 11.2), and
royalty reciprocity obligations (Section 5), which operate independently
of any single national legal system. Violation Records and License
Records in the Project Registry shall be recognized by all projects
operating under the OPL framework regardless of their governing law
jurisdiction. Where the Licensee is a Legal Entity with annual revenue
exceeding one million US dollars (or equivalent), the Licensee
consents to binding arbitration for enforcement of this License, and
any arbitration award shall be enforceable under the Convention on the
Recognition and Enforcement of Foreign Arbitral Awards (New York
Convention, 1958), to which over 170 jurisdictions are party.

### 15.2 Severability
If any provision of this License is held to be unenforceable or invalid
by a court of competent jurisdiction, such provision shall be modified
to the minimum extent necessary to make it enforceable and valid, and
the remaining provisions shall remain in full force and effect.

### 15.3 No Waiver
Failure of the License Steward or any Contributor to enforce any right or
provision of this License shall not constitute a waiver of that right
or provision, nor shall it affect the right to enforce such right or
provision in the future. No statement, promise, or agreement made by
an individual Guild Member or Contributor, unless formally ratified
by a vote of the Guild, shall create any exception to or modification
of the terms of this License.

### 15.4 Entire Agreement
This License, together with any applicable License Record, constitutes
the entire agreement between You and the License Steward regarding the Software
and supersedes any prior or contemporaneous agreements, representations,
or communications relating to the Software.

### 15.5 Smart Contract Integration (Guild Optional)
Where this License references on-chain royalty registries, License
Records, guild governance, or automated royalty distribution, the
functioning of the applicable smart contracts constitutes an
integrated part of the License. In the event of a conflict between
the text of this License and the behavior of a smart contract, this
License text shall control and the Steward shall update the contract
accordingly. If the blockchain or network hosting the primary
royalty registry becomes inoperable for a continuous period exceeding
thirty (30) days, the Steward must designate an alternative registry
mechanism (on a different chain, or off-chain with cryptographic
verification) and publish notice of the migration. During the
transition period, Commercial Use and AI Training Use rights remain
valid for existing Licensees, and new Licensees may register through
the alternative mechanism once designated. Failure by the Steward to
designate an alternative within ninety (90) days of inoperability
will not invalidate the License grants or relieve Licensees of their
obligation to register and pay once a functioning registry is restored.

### 15.6 Assignment (Solo-Friendly)
This License may not be assigned or transferred, in whole or in part,
without the prior written consent of the License Steward, except that a
License Record for Commercial Use or AI Training Use may be transferred as
part of a merger, acquisition, or sale of substantially all assets of
the Licensee's business, provided that the transferee agrees to be
bound by the terms of this License. Where the License Steward is a solo
copyright holder, their death, incapacity, or transfer of copyright
ownership shall transfer stewardship to their successor in interest
or designated executor, subject to the following conditions:
(i) The successor must be a natural person or legal entity capable of
    entering into binding agreements;
(ii) Fee schedules established by the successor must be set in good faith
    and be commercially reasonable, consistent with the fee schedules
    previously published by the predecessor Steward, adjusted only for
    inflation, material changes in project scope, or market conditions;
(iii) Existing Licensees shall retain all rights granted under their
    current License Records for the remainder of their licensed period,
    and renewal fees shall not exceed three (3) times the predecessor's
    most recently published applicable fee;
(iv) If the successor fails to assume stewardship responsibilities within
    ninety (90) days of transfer, stewardship and all associated
    obligations shall transfer to the community of Contributors, who
    shall elect an interim Steward through a majority vote of active
    Contributors within the following thirty (30) days.

### 15.7 Steward Removal for Malfeasance
A License Steward who is a human individual or Legal Entity (not a
multi-member Guild) may be removed from stewardship if all of the
following conditions are met:
(a) A petition signed by no fewer than twenty percent (20%) of unique
    Contributors with accepted Contributions in the preceding twelve (12)
    months is submitted to a publicly accessible Project Registry address
    designated for governance petitions;
(b) The petition states specific grounds for removal, limited to:
    (i) sustained failure to maintain the Software or Project Registry
        for a period exceeding six (6) months,
    (ii) imposition of fee schedules exceeding ten (10) times the
        predecessor Steward's most recent applicable fee without
        material expansion of project scope or services,
    (iii) refusal to accept Contributions that pass objective quality
        criteria published by the Steward,
    (iv) evidence of bad faith enforcement actions targeting
    legitimate Licensees, or
    (v) misappropriation of royalty funds intended for distribution to
    Contributors;
(c) The petition does NOT succeed on grounds of disagreement with
    fee levels within the Steward's normal discretion, technical
    decisions about the Software, or editorial decisions about
    accepted Contributions;
(d) A ninety (90) day cure period begins upon publication of the petition.
    If the Steward remedies the stated grounds within the cure period,
    the petition is voided. If the Steward does not remedy the grounds,
    stewardship transfers to the community of Contributors, who shall
    elect an interim Steward through a majority vote of active
    Contributors within the following thirty (30) days.
For Guild-governed projects (where the Steward is a Guild), this Section
does not apply; the Guild's own governance rules govern steward
replacement.

---

## SECTION 16: STEWARDSHIP SUNSET (CHANGE PROTOCOL)

### 16.1 Purpose
This License is designed to ensure fair compensation while the License
Steward actively maintains and governs the Software. To prevent the Software
from becoming "abandonware" with restrictive terms, this Section
defines a path to open source conversion.

### 16.2 The Conversion Trigger (Solo-Friendly)
If the License Steward (whether Guild or solo) fails to update the Project
Registry (e.g., via a governance vote, registry update, or version release)
for a continuous period of thirty-six (36) months ("The Sunset Period"),
**and** the number of Active Participants -- defined as individuals who
have made a Contribution, participated as a Collaborator (e.g., filed
issues, participated in discussion forums, provided feedback, or
participated in governance) within the preceding twelve (12) months --
has fallen below three (3), the restrictions in Sections 3, 4, and 5
regarding the Software shall automatically lift, and the Software shall
be considered licensed under the terms of the **Apache License, Version
2.0**. For solo Stewards, "governance" includes publication of fee
schedules, changelog, or public statements regarding the Software's
maintenance status.

### 16.3 Effect of Conversion
Upon conversion under Section 16.2:
(a) The Software is available under the Apache License, Version 2.0
    for all uses, including Commercial and AI Training Use, without
    fees or registration.
(b) This conversion is irrevocable.
(c) Previous License Records for Commercial or AI Training Use are
    honored as valid, but are no longer required.

### 16.4 Restarting the Clock
The Sunset Period is reset to zero if the License Steward publishes a new
version of the Software or updates the Registry with a governance action.
For the avoidance of doubt, a "governance action" requires substantive
maintenance activity, defined as at least one of: (i) a code commit or
merged contribution, (ii) publication of a versioned release, (iii) a
documented bug fix or security patch, or (iv) a published fee schedule
update. A mere public statement of intent to maintain the Software,
without accompanying substantive action, does not restart the Sunset Period.

### 16.5 Bad Faith Prevention
A deliberate campaign to exhaust a License Steward by overwhelming it
with frivolous governance proposals, spam, or harassment does not by
itself constitute abandonment for purposes of Section 16.2. The Steward
may establish anti-spam measures, minimum contribution requirements
for proposal submissions, or other governance safeguards at their
discretion. Such safeguards must be reasonable, publicly documented,
and applied uniformly -- they may not be used as a pretext to silence
legitimate community concern or prevent the Sunset Period from running.

## SECTION 17: WHISTLEBLOWER PROGRAM AND BOUNTY FUND

### 17.1 The Whistleblower Fund
To facilitate enforcement of this License, the License Steward shall
maintain a Bounty Pool funded by a percentage (e.g., 5%) of all Royalty
collections. This funds auditing, legal action, and rewards for reporting
violations. If the License Steward is a solo copyright holder (not a Guild),
they may instead fulfill this obligation by committing to pay a bounty
equal to the stated percentage of any recovered licensing fee or
estimated damages, payable upon successful enforcement.

### 17.2 Reporting Violations
Any individual or Automated Agent may report a violation to the License
Steward. Reports may be submitted anonymously through channels designated
by the License Steward (e.g., encrypted submission, anonymous tip line).
The License Steward shall not disclose the identity of the reporter to
the subject of the report without the reporter's explicit written consent,
except where disclosure is required by law or court order. The License
Steward shall take all reasonable steps to protect the reporter from
retaliation.

To prevent abuse of this system, a report will only result in a
Violation Record (Section 11.2(e)) or Enforcement Registry entry after
the License Steward has: (a) independently verified the reported
violation with documented evidence; (b) provided the subject of the
report with written notice and at least thirty (30) days to respond or
cure; and (c) determined that the violation is material -- meaning it
constitutes unlicensed commercial use, unlicensed AI Training Use, or
systematic evasion of royalty obligations, and does not include minor
administrative errors that have been cured or are in the process of
being cured. No more than one verified violation report per subject per
six (6) month period shall result in an Enforcement Registry entry,
unless the violations constitute distinct and substantively different
categories of infringement. Retaliation against a reporter, including
termination, demotion, harassment, or any adverse employment action
taken in response to a good-faith report under this Section, constitutes
a separate and actionable violation of this License and may subject the
retaliating party to enhanced damages under Section 10.4.

### 17.3 Bounty Payouts
Upon verification of a reported violation, the License Steward shall use
the Bounty Pool (or their personal commitment if solo) to reward the
reporter, calculated as a percentage of the recovered licensing fee or
estimated damages. For claims exceeding ten (10) times the applicable
License fee, the License Steward must obtain independent verification
of the violation from a third-party auditor, court ruling, or written
admission by the infringing party. The License Steward shall not
structure fee schedules or enforcement actions primarily to generate
bounty revenue for themselves or any designated agent.

### 17.4 Good Faith Reports
Reports must be submitted in good faith with factual basis. Any
individual who submits a false or knowingly misleading report with the
intent to harass, extort, or gain competitive advantage over another
Licensee shall be permanently barred from future bounty eligibility, and
the submitting party may be held liable for the legal costs incurred by
the falsely accused party and the administrative costs of investigating
the false report.

### 17.4 Amnesty for Good Faith Errors
If a Licensee's error is found to be a minor administrative oversight
(e.g., delayed renewal) and they cure the error within a 3-day window,
no bounty shall be paid to the reporter.

---

## SECTION 18: THIRD-PARTY DEPENDENCIES AND COMPATIBILITY

### 18.1 Separation of Licenses
The Software may include, link to, or depend upon third-party components
("Dependencies") that are licensed under terms other than this License
(e.g., MIT, Apache 2.0, GPL). A "Dependency" is defined as a component
that: (a) was created by an independent author or entity separate from
the License Steward; (b) is distributed under a publicly verifiable
and distinct license; and (c) is not a substantial reimplementation or
vendored copy of code originally authored under this OPL framework. The
terms of this License apply only to the specific code, documentation,
and assets created by the Contributor(s) and governed by the License
Steward. The terms of the Dependencies' respective licenses apply
exclusively to those components. This License is not incompatible with
permissive open-source licenses, and Dependencies remain under their
original terms regardless of their inclusion in the Software.

### 18.2 No Viral Effect
Nothing in this License shall be construed as extending the terms of this
License to any Dependency that is separately licensed under a different
license. Use, modification, or distribution of the Software does not
require Dependencies to be re-licensed under this Open-Pact License,
provided the Dependencies are kept as separate and distinct modules or
packages to the extent required by their own licenses. The "Derivative
Work" definition in Section 1.8 applies to the Software itself, not to
the distinct Dependencies it utilizes.

### 18.3 AI Training and Commercial Use Tracking
When the Software is used for AI Training (Section 4) or Commercial Use
(Section 3), the Licensee is responsible for ensuring compliance with the
terms of all Dependencies. The License Steward does not grant rights to
Dependencies. If a Dependency is also licensed under this OPL (or a later
version), the terms of that Dependency's specific License Steward apply
to that component. The Licensee must track and compensate each OPL-
licensed component independently.

For the avoidance of doubt, if a commercial product or service derives
substantial value from the Software and its Dependencies combined, the
Licensee shall not artificially segment revenue attribution to evade
Section 5.2 reciprocity obligations by claiming the substantive code is
"only a Dependency." Where a Dependency was originally authored under this
OPL framework (including vendored copies, forks, or reimplementations
retaining substantially the same functional characteristics), that
component shall be treated as part of the Software for purposes of
Section 5.2 Royalty Reciprocity, regardless of its declared dependency
status in any manifest file.

### 18.4 Good Faith Declaration
Contributors must declare all Dependencies and their respective licenses
in a machine-readable manifest file (e.g., LICENSE-THIRD-PARTY, NOTICE,
or DEPENDENCIES.json) included with the Software. Failure to accurately
declare Dependencies that results in license conflicts (e.g., including
copyleft code without disclosure or violating license compatibility)
constitutes a violation of Section 1.6.2 (Malicious Contribution).
The License Steward reserves the right to remove any Dependency that
violates its license terms or creates a legal risk for the Software.
Contributors and Licensees must cure any error in the Good Faith
Declaration within thirty (30) days of discovery or notification;
failure to cure constitutes a material breach.

### 18.5 Anti-Poisoning
The License Steward shall make reasonable efforts to ensure that
Dependencies do not introduce incompatible license combinations
(e.g., GPL copyleft in a commercial-only context) that would render
the Software unusable for a specific tier. If a Dependency's terms
are incompatible with the Software's intended use, the License
Steward must either replace the Dependency or prominently disclose
the incompatibility in the declaration so Licensees can make
informed decisions. Deliberate inclusion of incompatible
Dependencies to obstruct adoption constitutes a violation of
Section 1.6.2.

### 18.6 Shadow Dependency Prohibition
Where a commercial product derives substantial value from the
Software and its Dependencies combined, the Licensee shall not
artificially segment revenue attribution by claiming that
substantive code is "only a Dependency." Any Dependency that is a
vendored copy, fork, or reimplementation of code originally
authored under this OPL framework shall be treated as part of the
Software for purposes of Section 5.2 Royalty Reciprocity,
regardless of its declared dependency status.

---

END OF LICENSE

Open-Pact License v1.1 (OPL-1.1)
Designed for the age of AI. Governed by Guilds.

For registration, compliance verification, and guild governance:
https://open-pact.dev
