// Starlight configuration of the user documentation (ADR 0021).
// Built and deployed by .github/workflows/docs.yml.
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://docs.slidepilotapp.com',
  integrations: [
    starlight({
      title: 'SlidePilot Documentation',
      description: 'How to present PDF slides with SlidePilot on Mac, iPad and iPhone.',
      social: [
        { icon: 'github', label: 'SlidePilot on GitHub', href: 'https://github.com/SlidePilot/SlidePilot-Universal' },
      ],
      components: {
        // Adds the license line below each page.
        Footer: './src/components/Footer.astro',
      },
      sidebar: [
        { label: 'Overview', link: '/' },
        {
          label: 'Features',
          items: [
            { label: 'All Features', slug: 'features' },
            'features/presenting',
            'features/layout',
            'features/timing',
            'features/notes',
            'features/drawing',
            'features/curtain',
            'features/pointer',
            'features/remote',
            'features/beamer',
            'features/shortcuts',
            'features/settings',
          ],
        },
        'your-data',
        'pro',
        'faq',
        'troubleshooting',
        'changelog',
      ],
    }),
  ],
});
