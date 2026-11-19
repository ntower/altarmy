import {
  ActionIcon,
  Anchor,
  Button,
  Container,
  Group,
  useComputedColorScheme,
  useMantineColorScheme,
} from '@mantine/core'
import { AnimatePresence, MotionConfig, motion } from 'motion/react'
import classes from './App.module.css'
import { AccountControls } from './components/Account'
import { IconMoon, IconSun } from './components/icons'
import { Landing } from './components/Landing'
import { AddonPage, AdminPage, ManagePage, TrendsPage } from './components/Pages'
import { ProfitPage } from './components/Profit'
import { carriesCard, linkProps, previousRoute, useRoute, type Route } from './lib/router'
import { useSession } from './lib/session'

function NavLink({ to, label }: { to: Route; label: string }) {
  const route = useRoute()
  return (
    <Anchor className={classes.nav} underline="never" aria-current={route === to ? 'page' : undefined} {...linkProps(to)}>
      {label}
    </Anchor>
  )
}

/** Follows the OS until clicked; Mantine remembers the choice in localStorage. */
function ThemeToggle() {
  const { setColorScheme } = useMantineColorScheme()
  const scheme = useComputedColorScheme('dark')
  const next = scheme === 'dark' ? 'light' : 'dark'
  return (
    <ActionIcon
      variant="subtle"
      color="gray"
      size="lg"
      aria-label={`Switch to ${next} theme`}
      title={`Switch to ${next} theme`}
      onClick={() => setColorScheme(next)}
    >
      {scheme === 'dark' ? <IconSun size={20} /> : <IconMoon size={20} />}
    </ActionIcon>
  )
}

function Header() {
  const { admin } = useSession()
  return (
    <header className={classes.header}>
      <a className={classes.brand} aria-label="Alt Army, main page" {...linkProps('/')}>
        <img className={classes.mark} src="/logo.png" alt="" width={32} height={32} />
        <span className={classes.wordmark}>Alt Army</span>
      </a>
      <Group gap="md">
        <Group gap="md" component="nav" aria-label="Pages">
          <NavLink to="/manage" label="Manage" />
          {admin && <NavLink to="/trends" label="Trends" />}
          {admin && <NavLink to="/admin" label="Admin" />}
        </Group>
        <Button component="a" {...linkProps('/addon')}>
          Get the Addon
        </Button>
        <AccountControls />
        <ThemeToggle />
      </Group>
    </header>
  )
}

function Page({ route }: { route: Route }) {
  const { uid } = useSession()
  switch (route) {
    case '/addon':
      return <AddonPage />
    case '/profit':
      // Per user: what they chose on the Profit page is theirs.
      return <ProfitPage key={uid} />
    case '/manage':
      return <ManagePage />
    case '/trends':
      return <TrendsPage />
    case '/admin':
      return <AdminPage />
    default:
      return <Landing />
  }
}

export function App() {
  const route = useRoute()
  // The old page fades out over the new one (popLayout), so a showcase card on both (layoutId) moves across; when
  // it does, the new page shows at once and the card carries it in.
  const carried = carriesCard(previousRoute(), route)
  return (
    <MotionConfig reducedMotion="user">
      <Container size="xl" pb="xl" pos="relative">
        <Header />
        <AnimatePresence mode="popLayout" initial={false}>
          <motion.main
            key={route}
            initial={carried ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
          >
            <Page route={route} />
          </motion.main>
        </AnimatePresence>
      </Container>
    </MotionConfig>
  )
}
