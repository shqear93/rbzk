#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print usage information
function print_usage {
  echo -e "${YELLOW}Usage:${NC}"
  echo -e "  $0 [options]"
  echo -e ""
  echo -e "${YELLOW}Options:${NC}"
  echo -e "  --major         Create a major release (x.0.0)"
  echo -e "  --minor         Create a minor release (0.x.0)"
  echo -e "  --patch         Create a patch release (0.0.x) [default]"
  echo -e "  --dry-run       Show what would be done without making changes"
  echo -e "  --help          Show this help message"
  echo -e ""
  echo -e "${YELLOW}Examples:${NC}"
  echo -e "  $0 --minor      # Create a minor release"
  echo -e "  $0 --dry-run    # Show what would be done without making changes"
}

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
  echo -e "${RED}Error: GitHub CLI (gh) is not installed or not in PATH${NC}"
  echo -e "Please install it from https://cli.github.com/"
  exit 1
fi

# Check if git is available
if ! command -v git &> /dev/null; then
  echo -e "${RED}Error: Git is not installed or not in PATH${NC}"
  exit 1
fi

# Check GitHub authentication
if ! gh auth status &> /dev/null; then
  echo -e "${RED}Error: Not authenticated with GitHub CLI${NC}"
  echo -e "Please run 'gh auth login' first"
  exit 1
fi

# Default values
RELEASE_TYPE="patch"
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --major)
      RELEASE_TYPE="major"
      shift
      ;;
    --minor)
      RELEASE_TYPE="minor"
      shift
      ;;
    --patch)
      RELEASE_TYPE="patch"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      print_usage
      exit 1
      ;;
  esac
done

# Make sure we're in a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
  echo -e "${RED}Error: Not in a git repository${NC}"
  exit 1
fi

# Fetch from remote to ensure we have all tags and branches
echo -e "${GREEN}Fetching latest changes from remote...${NC}"
git fetch --tags --force

# Check for uncommitted changes
if ! git diff --quiet HEAD; then
  echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
  git status --short
  echo ""
  read -p "Continue anyway? (y/N) " CONTINUE_UNCOMMITTED
  if [[ ! "$CONTINUE_UNCOMMITTED" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Release creation cancelled${NC}"
    exit 1
  fi
fi

# Get the latest tag
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
echo -e "${GREEN}Latest tag:${NC} $LATEST_TAG"

# Extract version components
if [[ $LATEST_TAG =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  MAJOR="${BASH_REMATCH[1]}"
  MINOR="${BASH_REMATCH[2]}"
  PATCH="${BASH_REMATCH[3]}"
else
  echo -e "${YELLOW}Warning: Could not parse version from tag '$LATEST_TAG', assuming 0.0.0${NC}"
  MAJOR=0
  MINOR=0
  PATCH=0
fi

# Calculate new version based on release type
case "$RELEASE_TYPE" in
  major)
    NEW_MAJOR=$((MAJOR + 1))
    NEW_MINOR=0
    NEW_PATCH=0
    ;;
  minor)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$((MINOR + 1))
    NEW_PATCH=0
    ;;
  patch)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$MINOR
    NEW_PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="v$NEW_MAJOR.$NEW_MINOR.$NEW_PATCH"
echo -e "${GREEN}New version:${NC} $NEW_VERSION"

# Define the default release branch (usually main or master)
DEFAULT_RELEASE_BRANCH="main"
# Check if main exists, otherwise try master
if ! git show-ref --verify --quiet refs/remotes/origin/main; then
  if git show-ref --verify --quiet refs/remotes/origin/master; then
    DEFAULT_RELEASE_BRANCH="master"
  fi
fi

# Get the current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
echo -e "${GREEN}Current branch:${NC} $CURRENT_BRANCH"

# Check if we're on the default release branch
if [ "$CURRENT_BRANCH" != "$DEFAULT_RELEASE_BRANCH" ]; then
  echo -e "${YELLOW}Warning: You are not on the $DEFAULT_RELEASE_BRANCH branch${NC}"
  echo -e "${RED}Releases should be created from the $DEFAULT_RELEASE_BRANCH branch.${NC}"

  # If on develop, explain the proper workflow and offer to merge
  if [ "$CURRENT_BRANCH" = "develop" ]; then
    echo -e "${YELLOW}You are on the develop branch. The proper workflow is:${NC}"
    echo -e "1. Merge develop into $DEFAULT_RELEASE_BRANCH"
    echo -e "2. Create the release from $DEFAULT_RELEASE_BRANCH"
    echo -e ""

    read -p "Would you like to merge develop into $DEFAULT_RELEASE_BRANCH now? (y/N) " MERGE_DEVELOP
    if [[ "$MERGE_DEVELOP" =~ ^[Yy]$ ]]; then
      echo -e "${GREEN}Switching to $DEFAULT_RELEASE_BRANCH branch...${NC}"
      git checkout $DEFAULT_RELEASE_BRANCH

      # Make sure we have the latest changes
      echo -e "${GREEN}Pulling latest changes from $DEFAULT_RELEASE_BRANCH...${NC}"
      git pull origin $DEFAULT_RELEASE_BRANCH

      echo -e "${GREEN}Merging develop into $DEFAULT_RELEASE_BRANCH...${NC}"
      if git merge develop; then
        echo -e "${GREEN}Successfully merged develop into $DEFAULT_RELEASE_BRANCH${NC}"

        # Ask to push the merge to remote
        read -p "Push the merged changes to remote? (Y/n) " PUSH_MERGE
        if [[ ! "$PUSH_MERGE" =~ ^[Nn]$ ]]; then
          echo -e "${GREEN}Pushing merged changes to remote...${NC}"
          git push origin $DEFAULT_RELEASE_BRANCH
        fi

        CURRENT_BRANCH=$DEFAULT_RELEASE_BRANCH
        echo ""
      else
        echo -e "${RED}Merge conflict! Please resolve conflicts manually and try again.${NC}"
        exit 1
      fi
    else
      # Ask to switch to the release branch
      read -p "Switch to $DEFAULT_RELEASE_BRANCH branch? (Y/n) " SWITCH_BRANCH
      if [[ ! "$SWITCH_BRANCH" =~ ^[Nn]$ ]]; then
        echo -e "${GREEN}Switching to $DEFAULT_RELEASE_BRANCH branch...${NC}"
        git checkout $DEFAULT_RELEASE_BRANCH
        CURRENT_BRANCH=$DEFAULT_RELEASE_BRANCH
        echo ""
      else
        echo -e "${RED}Release creation cancelled${NC}"
        echo -e "Please switch to $DEFAULT_RELEASE_BRANCH branch and try again."
        exit 1
      fi
    fi
  else
    # Not on develop, just ask to switch to the release branch
    read -p "Switch to $DEFAULT_RELEASE_BRANCH branch? (Y/n) " SWITCH_BRANCH
    if [[ ! "$SWITCH_BRANCH" =~ ^[Nn]$ ]]; then
      echo -e "${GREEN}Switching to $DEFAULT_RELEASE_BRANCH branch...${NC}"
      git checkout $DEFAULT_RELEASE_BRANCH
      CURRENT_BRANCH=$DEFAULT_RELEASE_BRANCH
      echo ""
    else
      echo -e "${RED}Release creation cancelled${NC}"
      echo -e "Please switch to $DEFAULT_RELEASE_BRANCH branch and try again."
      exit 1
    fi
  fi
fi

# Check if branch is behind remote
REMOTE_BRANCH="origin/$CURRENT_BRANCH"
git fetch origin $CURRENT_BRANCH
BEHIND_COUNT=$(git rev-list --count HEAD..$REMOTE_BRANCH 2>/dev/null || echo "0")

if [ "$BEHIND_COUNT" -gt 0 ]; then
  echo -e "${YELLOW}Warning: Your branch is behind the remote by $BEHIND_COUNT commit(s)${NC}"
  echo -e "It's recommended to pull the latest changes before creating a release."
  read -p "Pull latest changes? (Y/n) " PULL_CHANGES
  if [[ ! "$PULL_CHANGES" =~ ^[Nn]$ ]]; then
    echo -e "${GREEN}Pulling latest changes...${NC}"
    # Check if there are uncommitted changes
    if git diff --quiet HEAD; then
      # No uncommitted changes, safe to use rebase
      git pull --rebase origin $CURRENT_BRANCH
    else
      # Uncommitted changes exist, use regular pull
      git pull origin $CURRENT_BRANCH
    fi
    echo ""
  fi
fi

# Generate release notes
echo -e "${GREEN}Generating release notes...${NC}"
RELEASE_NOTES=$(git log --pretty=format:"- %s (%h)" $LATEST_TAG..HEAD)

if [ -z "$RELEASE_NOTES" ]; then
  echo -e "${YELLOW}Warning: No commits found since $LATEST_TAG${NC}"
  RELEASE_NOTES="No significant changes since $LATEST_TAG"
else
  # Count the number of commits by type
  FEAT_COUNT=$(echo "$RELEASE_NOTES" | grep -c "^- feat" || true)
  FIX_COUNT=$(echo "$RELEASE_NOTES" | grep -c "^- fix" || true)
  REFACTOR_COUNT=$(echo "$RELEASE_NOTES" | grep -c "^- refactor" || true)
  DOCS_COUNT=$(echo "$RELEASE_NOTES" | grep -c "^- docs" || true)

  # Create a summary section
  SUMMARY="## Summary\n\n"
  [ $FEAT_COUNT -gt 0 ] && SUMMARY+="- $FEAT_COUNT new features\n"
  [ $FIX_COUNT -gt 0 ] && SUMMARY+="- $FIX_COUNT bug fixes\n"
  [ $REFACTOR_COUNT -gt 0 ] && SUMMARY+="- $REFACTOR_COUNT refactorings\n"
  [ $DOCS_COUNT -gt 0 ] && SUMMARY+="- $DOCS_COUNT documentation updates\n"

  # Organize commits by type
  FEATURES=$(echo "$RELEASE_NOTES" | grep "^- feat" || echo "")
  FIXES=$(echo "$RELEASE_NOTES" | grep "^- fix" || echo "")
  REFACTORS=$(echo "$RELEASE_NOTES" | grep "^- refactor" || echo "")
  DOCS=$(echo "$RELEASE_NOTES" | grep "^- docs" || echo "")
  OTHER=$(echo "$RELEASE_NOTES" | grep -v "^- feat\|^- fix\|^- refactor\|^- docs" || echo "")

  # Format the final release notes
  RELEASE_NOTES="$SUMMARY\n"
  [ ! -z "$FEATURES" ] && RELEASE_NOTES+="\n## Features\n\n$FEATURES\n"
  [ ! -z "$FIXES" ] && RELEASE_NOTES+="\n## Bug Fixes\n\n$FIXES\n"
  [ ! -z "$REFACTORS" ] && RELEASE_NOTES+="\n## Refactorings\n\n$REFACTORS\n"
  [ ! -z "$DOCS" ] && RELEASE_NOTES+="\n## Documentation\n\n$DOCS\n"
  [ ! -z "$OTHER" ] && RELEASE_NOTES+="\n## Other Changes\n\n$OTHER\n"
fi

# Show release notes
echo -e "${GREEN}Release notes:${NC}"
echo -e "$RELEASE_NOTES"

# If this is a dry run, exit here
if [ "$DRY_RUN" = true ]; then
  echo -e "\n${YELLOW}Dry run - no changes made${NC}"
  exit 0
fi

# Confirm with the user
echo -e "\n${YELLOW}Ready to create release $NEW_VERSION from branch $CURRENT_BRANCH${NC}"
read -p "Continue? (y/N) " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo -e "${RED}Release creation cancelled${NC}"
  exit 1
fi

# Create and push the tag
echo -e "\n${GREEN}Creating and pushing tag $NEW_VERSION...${NC}"
git tag -a "$NEW_VERSION" -m "Release $NEW_VERSION"

# Check if tag already exists on remote
if git ls-remote --tags origin | grep -q "$NEW_VERSION$"; then
  echo -e "${YELLOW}Warning: Tag $NEW_VERSION already exists on remote${NC}"
  read -p "Force push the tag? (y/N) " FORCE_PUSH
  if [[ "$FORCE_PUSH" =~ ^[Yy]$ ]]; then
    git push --force origin "$NEW_VERSION"
  else
    echo -e "${RED}Release creation cancelled${NC}"
    git tag -d "$NEW_VERSION"
    exit 1
  fi
else
  git push origin "$NEW_VERSION"
fi

# Create the GitHub release
echo -e "\n${GREEN}Creating GitHub release...${NC}"
RELEASE_NOTES_FILE=$(mktemp)
echo -e "$RELEASE_NOTES" > "$RELEASE_NOTES_FILE"

gh release create "$NEW_VERSION" \
  --title "Release $NEW_VERSION" \
  --notes-file "$RELEASE_NOTES_FILE"

rm "$RELEASE_NOTES_FILE"

echo -e "\n${GREEN}Release $NEW_VERSION created successfully!${NC}"
echo -e "View it at: $(gh release view "$NEW_VERSION" --json url -q .url)"

# Remind about the CI/CD workflow
echo -e "\n${YELLOW}Note:${NC} The CI/CD workflow should automatically publish this release to RubyGems."
